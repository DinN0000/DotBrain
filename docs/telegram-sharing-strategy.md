# Telegram Vibe Community Sharing Strategy

## Target: Vibe Coding Community

바이브 코딩 커뮤니티의 특성:
- 개발자이면서 AI 도구에 관심이 높음
- "흐름"과 "감각적인 개발 경험"을 중시
- 과장된 마케팅보다 진짜 문제 해결에 반응
- 짧고 임팩트 있는 메시지 선호

---

## Option A: 문제 공감형 (Recommended)

> 노트앱 쓰면서 "나중에 정리해야지" 하고 안 한 적 있으면 읽어보세요.
>
> DotBrain이라는 macOS 메뉴바 앱을 만들었습니다.
> 인박스에 파일 던지면 AI가 내용 읽고 PARA 구조로 자동 분류해줍니다.
> 프론트매터, 태그, 관련 노트 연결, MOC 생성까지 전부 자동.
>
> 근데 진짜 포인트는 따로 있어요.
> 이렇게 구조화된 볼트를 Claude Code나 Cursor가 읽으면
> AI가 내 지식을 제대로 이해하고 활용할 수 있게 됩니다.
> 정리가 잘 될수록 AI가 똑똑해지는 구조.
>
> Swift로 만든 네이티브 앱이고, 의존성은 ZIPFoundation 하나뿐입니다.
> Claude/Gemini 듀얼 프로바이더에 자동 폴백까지 있어서 안 죽어요.
>
> 설치: `curl -sL https://raw.githubusercontent.com/DinN0000/DotBrain/main/install.sh | bash`
> GitHub: https://github.com/DinN0000/DotBrain

**왜 이 버전이 좋은가:** "나중에 정리해야지"는 거의 모든 개발자가 공감하는 포인트. 문제 인식 -> 해결책 -> 숨은 가치(AI 성능 향상) 순서로 자연스럽게 관심을 끈다.

---

## Option B: 기술 디테일형 (개발자 밀도 높은 커뮤니티)

> macOS 메뉴바 PKM 앱 만들었습니다. Swift 네이티브.
>
> 하는 일:
> - 인박스에 파일 넣으면 AI가 PARA 분류 (2-stage: Haiku/Flash -> Sonnet/Pro)
> - PDF, DOCX, PPTX, XLSX, 이미지 전부 내용 추출
> - Obsidian 호환 frontmatter + wiki-link 자동 생성
> - MOC(Map of Content) 폴더별 자동 갱신
> - SHA256 중복 감지, 폴더 플랫화, 오분류 자동 교정
> - CLAUDE.md, AGENTS.md, .cursorrules 볼트에 자동 생성
>
> 기술 포인트:
> - Claude + Gemini 듀얼 프로바이더, 자동 폴백
> - Actor 기반 동시성 (lock-free)
> - 스트리밍 I/O (1MB 청크, 대용량 파일 안전)
> - API 키 AES-GCM 암호화 (하드웨어 UUID 바인딩)
> - 외부 의존성 ZIPFoundation 단 하나
>
> GitHub: https://github.com/DinN0000/DotBrain
> 설치: `curl -sL https://raw.githubusercontent.com/DinN0000/DotBrain/main/install.sh | bash`

**왜 이 버전이 좋은가:** 바이브 코딩 커뮤니티에서 기술 깊이를 보여주면 신뢰가 생긴다. "의존성 하나", "Actor 기반", "듀얼 프로바이더" 같은 키워드가 개발자 눈에 걸린다.

---

## Option C: 한 줄 훅 + 스크린샷형 (최소 텍스트)

> 노트 정리 AI한테 시키는 앱 만들었습니다.
> 파일 던지면 알아서 분류하고, 그 구조를 AI가 그대로 활용합니다.
>
> [스크린샷/GIF 첨부]
>
> https://github.com/DinN0000/DotBrain

**왜 이 버전이 좋은가:** 텔레그램은 긴 글을 잘 안 읽는다. 한 줄로 호기심 유발 -> 스크린샷으로 증명 -> 링크로 마무리. 단, 스크린샷이나 GIF가 반드시 있어야 효과적.

---

## Option D: 바이브 코딩 맥락 연결형

> 바이브 코딩할 때 AI한테 "이 프로젝트 맥락 파악해"라고 하면
> 제대로 못 읽는 경우 많지 않나요?
>
> 그게 결국 내 지식이 구조화가 안 돼서 그런 겁니다.
> AI가 읽을 수 있는 형태로 정리되어 있으면 성능이 확 달라져요.
>
> 그래서 그 정리 자체를 AI한테 시키는 앱을 만들었습니다.
> 인박스에 파일 넣으면 PARA 분류, frontmatter, wiki-link, MOC까지 자동.
> Obsidian 볼트에 CLAUDE.md랑 AGENTS.md도 심어줘서
> Claude Code가 볼트 구조를 바로 이해합니다.
>
> macOS 네이티브 메뉴바 앱이고, Swift로 만들었어요.
> https://github.com/DinN0000/DotBrain

**왜 이 버전이 좋은가:** "바이브 코딩" 커뮤니티의 핵심 페인포인트(AI 맥락 이해 부족)를 직접 건드린다. "AI가 잘 읽게 정리하는 것 자체를 AI가 해준다"는 메타적 가치가 이 커뮤니티에서 가장 공감될 수 있다.

---

## Sharing Tips

### Do
- **스크린샷/GIF 첨부**: 메뉴바 아이콘 `·_·` -> 분류 진행중 -> 완료까지의 flow
- **설치 원라이너 강조**: `curl` 한 줄이면 된다는 점이 진입장벽을 낮춤
- **"Obsidian 호환" 명시**: Obsidian 사용자가 많은 커뮤니티에서 큰 장점
- **실제 사용 사례 공유**: "어제 논문 10개를 인박스에 넣었더니 5분만에 전부 분류됐다" 같은 구체적 경험

### Don't
- 기능 나열만 하지 말 것 (왜 필요한지가 먼저)
- "최고의", "혁신적인" 같은 과장 표현 쓰지 말 것 (바이브 커뮤니티는 이런 거에 반감)
- 너무 긴 글 쓰지 말 것 (텔레그램 특성상 스크롤 안 함)
- 다른 앱 비교/디스하지 말 것

### Timing
- 평일 저녁 9-11시 or 주말 오후가 반응 좋은 시간대
- 다른 사람의 공유 직후보다는 대화가 잠잠할 때

### Follow-up
- 첫 공유 후 반응 오면 기술 디테일 답변으로 깊이 보여주기
- "이거 어떻게 만들었어요?" 질문에 대비해서 아키텍처 요약 준비
- 피드백 받으면 바로 반영하고 "반영했습니다" 공유 -> 신뢰 구축
