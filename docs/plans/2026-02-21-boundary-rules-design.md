# Architecture: Boundary Rules + Layer Separation

**Date**: 2026-02-21
**Status**: Approved
**Scope**: AppState refactoring + code placement rules

## Problem

AppState.swift (982줄)가 UI state 관리와 business logic을 혼합하고 있다. 특히 `startVaultCheck()` (175줄)이 5-phase pipeline 로직을 인라인으로 포함. InboxProcessor, FolderReorganizer는 이미 `Sources/Pipeline/`에 분리되어 있으나 VaultCheck만 AppState에 남아있어 일관성이 없다.

## Decision

**Option A: Boundary Rules + Layer Separation** 선택. Protocol/DI 없이 경계만 정리.

### Rationale
- 1인 개발, 테스트 코드 0, 39개 서비스 → Full DI는 over-engineering
- 경계 규칙만 명확히 하면 동일한 효과 (코드가 엉뚱한 곳에 안 들어감)
- 기존 패턴(Pipeline 객체 + callback)을 그대로 활용

## Changes

### 1. VaultCheckPipeline 추출

`Sources/Pipeline/VaultCheckPipeline.swift` (새 파일, ~200줄)

- AppState.startVaultCheck() 인라인 로직 전체 이동
- collectRepairedFiles(), collectAllMdFiles() 헬퍼도 함께 이동
- Progress callback으로 UI state 업데이트 (InboxProcessor와 동일 패턴)

AppState.startVaultCheck()는 guard + pipeline 생성 + Task.detached 호출만 남김 (~30줄)

### 2. CLAUDE.md Code Placement Rules

새 기능 추가 시 코드가 어디로 가야 하는지 명시:
- Pipeline: multi-phase 처리 로직
- Services: 단일 책임 유틸리티
- AppState: @Published 속성, navigation, 얇은 파이프라인 래퍼
- UI View: AppState를 통한 간접 호출만

### 3. 건드리지 않는 것

- startProcessing/startReorganizing/startBatchReorganizing — 이미 Pipeline 패턴 준수
- UI Views, Services, Models — 변경 없음

## Impact

| Metric | Before | After |
|--------|--------|-------|
| AppState.swift | 982줄 | ~760줄 |
| VaultCheckPipeline.swift | 없음 | ~200줄 |
| 기능 변경 | - | 없음 |
| Pipeline 패턴 일관성 | 3/4 | 4/4 |
