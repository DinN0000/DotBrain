# MOC Lifecycle Design Document

> **Summary**: MOC 생명주기 전체를 구조적으로 보장하는 설계. 루트 MOC 버그 수정 + VaultReorganizer MOC 갱신 추가 + 비용 통일.
>
> **Project**: DotBrain
> **Author**: hwai
> **Date**: 2026-02-18
> **Status**: Draft
> **Planning Doc**: [moc-lifecycle.plan.md](../01-plan/features/moc-lifecycle.plan.md)

---

## 1. Overview

### 1.1 Design Goals

1. **모든 파이프라인 완료 후 MOC 최신 상태 보장** — 인박스/폴더재정리/전체재정리/볼트점검 어디서든 실행 후 MOC가 현실과 일치
2. **루트 MOC 품질 복원** — 태그 집계, Project별 문서 목록이 실제로 출력되도록 버그 수정
3. **비용 추정 정확성** — 모든 파이프라인에서 동일한 단가 사용

### 1.2 Design Principles

- **기존 패턴 재사용**: FolderReorganizer의 MOC 갱신 패턴을 VaultReorganizer에 동일 적용
- **방어적 프로그래밍**: 태그 집계 실패 시 디버그 로그로 원인 추적 가능
- **최소 변경**: 3개 파일만 수정, 새 파일 없음

---

## 2. Architecture

### 2.1 MOC 갱신 흐름 (현재 vs 목표)

```
현재 상태:
┌──────────────┐   ┌──────────────────┐   ┌───────────────────┐
│ InboxProcessor│   │ FolderReorganizer │   │ VaultReorganizer  │
│              │   │                  │   │                   │
│ updateMOCs() │   │ generateMOC()    │   │ (MOC 갱신 없음) X │
│      ✓       │   │ updateMOCs() ✓   │   │                   │
└──────────────┘   └──────────────────┘   └───────────────────┘

목표 상태:
┌──────────────┐   ┌──────────────────┐   ┌───────────────────┐
│ InboxProcessor│   │ FolderReorganizer │   │ VaultReorganizer  │
│              │   │                  │   │                   │
│ updateMOCs() │   │ generateMOC()    │   │ updateMOCs() ✓    │
│      ✓       │   │ updateMOCs() ✓   │   │   (FR-02 추가)    │
└──────────────┘   └──────────────────┘   └───────────────────┘

공통:
┌──────────────────────────────────────────────────────────┐
│                    MOCGenerator                           │
│                                                          │
│  generateMOC()          → 하위 폴더 MOC (태그 O)          │
│  updateMOCsForFolders() → 하위 + 루트 MOC 갱신            │
│  generateCategoryRootMOC() → 루트 MOC (태그 집계 버그) X  │
│  regenerateAll()        → 전체 재생성 (볼트점검에서 호출)   │
└──────────────────────────────────────────────────────────┘
```

### 2.2 변경 대상 파일

| File | Lines | Change | FR |
|------|-------|--------|-----|
| `Sources/Services/MOCGenerator.swift` | 136-231 | `generateCategoryRootMOC()` 디버그 + 버그 수정 | FR-01 |
| `Sources/Pipeline/VaultReorganizer.swift` | 176-223 | `execute()` 끝에 MOC 갱신 추가 | FR-02 |
| `Sources/Pipeline/VaultReorganizer.swift` | 140 | `0.001` → `0.005` | FR-03 |
| `Sources/Pipeline/FolderReorganizer.swift` | 133 | `0.001` → `0.005` | FR-03 |

---

## 3. FR-01: 루트 MOC 태그/문서목록 버그 수정

### 3.1 현상

- `generateCategoryRootMOC()`가 실행되면 루트 MOC(예: `1_Project.md`)에:
  - frontmatter `tags:` 필드 누락
  - 폴더 목록에 `[tag1, tag2]` 라벨 누락
  - Project 카테고리에서 per-document 목록 누락
- 하위 MOC(예: `Si-FLAP/Si-FLAP.md`)에는 태그 정상 존재

### 3.2 코드 분석 결과

**정적 분석**: 코드 로직은 올바르게 보임

```swift
// MOCGenerator.swift:150-158 — 하위 MOC에서 태그 읽기
let subMOCPath = (entryPath as NSString).appendingPathComponent("\(entry).md")
var folderTags: [String] = []
if let content = try? String(contentsOfFile: subMOCPath, encoding: .utf8) {
    let (frontmatter, _) = Frontmatter.parse(markdown: content)
    folderTags = frontmatter.tags  // ← 여기서 빈 배열이 반환됨
}
```

- `Frontmatter.parse()` → `parseYamlSimple()` → inline array 처리 로직 문제 없음
- `stringify()` → `createDefault()` → 태그 전달 경로 문제 없음
- 하위 MOC의 summary는 정상 파싱됨 (같은 parse 호출에서)
- **하지만 런타임에서 tags는 빈 배열** → 정적 분석으로 원인 특정 불가

**런타임 증거**:
- `1_Project.md` body에 `(4개)`, `(17개)` 등 fileCount 정상 → `mdFiles` 비어있지 않음
- summary 필드 정상 → 파일 읽기 자체는 성공
- 하지만 `[tag1, tag2]` 라벨 없음 → `folder.tags` 비어있음
- per-document 목록 없음 → `folder.docs` 비어있음

### 3.3 디버그 전략

`generateCategoryRootMOC()` 에 디버그 로그를 추가하여 런타임 값을 추적:

```swift
// Step 1: 하위 MOC 읽기 시 로그
if let content = try? String(contentsOfFile: subMOCPath, encoding: .utf8) {
    let (frontmatter, _) = Frontmatter.parse(markdown: content)
    summary = frontmatter.summary ?? ""
    folderTags = frontmatter.tags
    print("[MOCGenerator] ROOT-DEBUG \(entry): tags=\(folderTags.count), summary=\(summary.prefix(30))")
} else {
    print("[MOCGenerator] ROOT-DEBUG \(entry): MOC 읽기 실패 — \(subMOCPath)")
}

// Step 2: per-document 읽기 시 로그
if para == .project {
    print("[MOCGenerator] ROOT-DEBUG \(entry): mdFiles=\(mdFiles.count)")
    for file in mdFiles.sorted().prefix(10) {
        let filePath = (entryPath as NSString).appendingPathComponent(file)
        if let fileContent = try? String(contentsOfFile: filePath, encoding: .utf8) {
            let (fileFM, _) = Frontmatter.parse(markdown: fileContent)
            let tagStr = fileFM.tags.prefix(3).joined(separator: ", ")
            docs.append((name: baseName, tags: tagStr, summary: fileFM.summary ?? ""))
            print("[MOCGenerator] ROOT-DEBUG   doc: \(baseName), tags=\(tagStr)")
        } else {
            print("[MOCGenerator] ROOT-DEBUG   doc FAIL: \(file)")
        }
    }
}

// Step 3: 최종 태그 집계 로그
print("[MOCGenerator] ROOT-DEBUG categoryTags=\(categoryTags.count), topTags=\(topTags)")
```

### 3.4 예상 원인과 대응

| # | 원인 후보 | 확인 방법 | 수정 방향 |
|---|----------|----------|----------|
| A | `Frontmatter.parse()` inline array 파싱 에지 케이스 | 로그에서 `tags=0`이면서 MOC 파일에 태그 존재 | 파서 수정 또는 fallback 파싱 추가 |
| B | `try?` 에서 파일 읽기 실패 (인코딩/경로) | 로그에서 "읽기 실패" 출력 | 에러 로깅 추가, encoding fallback |
| C | `regenerateAll()` 실행 순서 이슈 | 로그 타임스탬프 비교 | TaskGroup await 확인 |
| D | 다른 코드가 루트 MOC를 덮어씀 | 로그에서 태그 정상 후 파일이 다시 변경됨 | 호출 추적 |

### 3.5 방어적 수정 (디버그와 동시 적용)

디버그 로그 외에, 태그 집계 실패 시 경고를 출력하는 방어 코드 추가:

```swift
// generateCategoryRootMOC() 내부, 태그 집계 후
if topTags.isEmpty && !subfolders.isEmpty {
    // 하위 폴더가 있는데 태그가 0개면 비정상
    let tagStatus = subfolders.map { "\($0.name):\($0.tags.count)" }.joined(separator: ", ")
    print("[MOCGenerator] WARNING: 루트 MOC 태그 0개 — 하위 폴더 태그 상태: \(tagStatus)")
}
```

---

## 4. FR-02: VaultReorganizer MOC 갱신 추가

### 4.1 현재 상태

```swift
// VaultReorganizer.swift:176-223 — execute() 현재 코드
func execute(plan: [FileAnalysis]) async throws -> [ProcessedFileResult] {
    let selected = plan.filter(\.isSelected)
    // ... 파일 이동 루프 ...
    onProgress?(1.0, "완료!")
    return results
    // ← MOC 갱신 없이 종료
}
```

### 4.2 수정 설계

FolderReorganizer의 기존 패턴(lines 237-248)을 따름:

```swift
// VaultReorganizer.swift — execute() 끝에 추가
func execute(plan: [FileAnalysis]) async throws -> [ProcessedFileResult] {
    let selected = plan.filter(\.isSelected)
    guard !selected.isEmpty else { return [] }

    let mover = FileMover(pkmRoot: pkmRoot)
    var results: [ProcessedFileResult] = []

    for (i, analysis) in selected.enumerated() {
        // ... 기존 파일 이동 코드 (변경 없음) ...
    }

    // ── FR-02: MOC 갱신 추가 ──
    // 이동된 파일의 대상 폴더 수집
    let affectedFolders = Set(results.filter(\.isSuccess).compactMap { result -> String? in
        let dir = (result.targetPath as NSString).deletingLastPathComponent
        return dir.isEmpty ? nil : dir
    })

    if !affectedFolders.isEmpty {
        let mocGenerator = MOCGenerator(pkmRoot: pkmRoot)
        await mocGenerator.updateMOCsForFolders(affectedFolders)
    }
    // ── FR-02 끝 ──

    onProgress?(1.0, "완료!")
    return results
}
```

### 4.3 영향 범위

- `updateMOCsForFolders()`는 내부에서:
  1. 각 폴더의 하위 MOC 재생성 (`generateMOC()`)
  2. 부모 카테고리의 루트 MOC 재생성 (`generateCategoryRootMOC()`)
- 이미 InboxProcessor, FolderReorganizer에서 동일 패턴 사용 중
- 추가 API 비용: 이동된 폴더 수 × $0.0005 (fast model 사용)

---

## 5. FR-03: 비용 추정 통일

### 5.1 현재 값

| Pipeline | File:Line | Current | Target |
|----------|-----------|---------|--------|
| InboxProcessor | (이미 갱신됨) | $0.005 | $0.005 |
| VaultReorganizer | `VaultReorganizer.swift:140` | $0.001 | $0.005 |
| FolderReorganizer | `FolderReorganizer.swift:133` | $0.001 | $0.005 |

### 5.2 수정

```swift
// VaultReorganizer.swift:140
// Before:
let estimatedCost = Double(inputs.count) * 0.001
// After:
let estimatedCost = Double(inputs.count) * 0.005

// FolderReorganizer.swift:133
// Before:
let estimatedCost = Double(inputs.count) * 0.001
// After:
let estimatedCost = Double(inputs.count) * 0.005
```

---

## 6. Implementation Order

| # | FR | Task | File | Estimated Lines |
|---|-----|------|------|----------------|
| 1 | FR-01 | 디버그 로그 + 방어 코드 추가 | `MOCGenerator.swift` | +15 |
| 2 | FR-01 | 빌드 → 볼트점검 실행 → 로그 확인 → 원인 특정 후 수정 | `MOCGenerator.swift` | TBD |
| 3 | FR-02 | `execute()` 끝에 MOC 갱신 코드 추가 | `VaultReorganizer.swift` | +10 |
| 4 | FR-03 | 비용 값 2곳 변경 | `VaultReorganizer.swift`, `FolderReorganizer.swift` | 2 |
| 5 | ALL | `swift build` 경고 0개 확인 | - | - |

---

## 7. Test Plan

### 7.1 FR-01 검증

```
1. swift build (경고 0개)
2. DotBrain 실행 → 볼트점검 실행
3. 콘솔 로그에서 [MOCGenerator] ROOT-DEBUG 확인
4. 루트 MOC 파일 확인:
   - frontmatter에 tags: 필드 존재
   - 폴더 목록에 [tag1, tag2] 라벨 존재
   - 1_Project.md에 per-document 목록 존재
```

### 7.2 FR-02 검증

```
1. 전체 재정리(VaultReorganizer) 실행
2. 이동된 파일의 대상 폴더 MOC가 갱신되었는지 확인
3. 루트 MOC도 갱신되었는지 확인
```

### 7.3 FR-03 검증

```
1. VaultReorganizer.scan() 실행 시 estimatedCost가 파일수 × 0.005
2. FolderReorganizer.process() 실행 시 estimatedCost가 파일수 × 0.005
```

---

## 8. Success Criteria

- [ ] 볼트점검 후 루트 MOC frontmatter에 `tags:` 필드 존재 (10개 이내)
- [ ] 볼트점검 후 1_Project 루트 MOC에 프로젝트별 문서 목록 존재
- [ ] 전체 재정리 후 영향받은 폴더의 MOC가 최신 상태
- [ ] 비용 추정이 $0.005/파일로 통일
- [ ] `swift build` 경고 0개

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-18 | Initial design — code analysis + debug strategy | hwai |
