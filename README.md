# Lim_claude

코딩 에이전트가 "다 됐어요"라고 말하기 전에 실제로 실행해서 확인하게 만드는 규칙과 도구예요. 레포 안에 설치하고 커밋하면 그 레포를 클론하는 사람 모두가 같은 규칙을 쓰게 돼요.

Anthropic 블로그 글 [How the Claude Code team thinks about verification](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification/)을 참고했어요.

## 레포에 설치되는 것

| 위치 | 내용 | 누가 쓰나 |
| --- | --- | --- |
| `AGENTS.md` | 작업 순서, 검증, 테스트, 문서, Git/PR, 머지, 서브에이전트 규칙. `Cargo.toml`이 있으면 Rust 규칙도 들어가요 | AGENTS.md를 읽는 모든 에이전트 |
| `.claude/skills/verify/SKILL.md` | 변경을 실제로 돌려 보고 증거를 남기는 절차 | Claude Code (`verify` 스킬), 다른 에이전트는 AGENTS.md가 이 파일을 가리켜요 |
| `.claude/hooks/commit-gate.sh` | `git commit` 직전에 검사를 돌리고 실패하면 커밋을 막는 훅 | Claude Code |
| `.claude/settings.json` | 위 훅 등록 한 줄 | Claude Code |
| `.claude/lim_claude/` | 설치한 파일 목록(`manifest`)과 원래 있던 AGENTS.md, CLAUDE.md 원본(`*.orig`) | `lim.sh` |
| `.gitignore` | `.claude/`가 무시되는 레포에서만, Lim_claude 파일과 `.claude/verify.sh`를 추적하게 하는 블록 | git |

### 처음 설치할 때 정리하는 것

1. **기존 `AGENTS.md`:** 내용을 `.claude/lim_claude/AGENTS.md.orig`로 옮기고, `AGENTS.md`는 Lim_claude 블록으로 새로 써요. 레포 전용 규칙이 필요하면 블록의 END 줄 아래에 쓰세요. 업데이트해도 그 부분은 유지돼요.
2. **`CLAUDE.md`, `.claude/CLAUDE.md`:** 지워요. Claude Code는 `CLAUDE.md`가 있으면 `AGENTS.md`를 읽지 않기 때문이에요. 원본은 `.claude/lim_claude/`에 `.orig`로 보관해요.
3. **`.gitignore`:** `.claude/`가 통째로 무시되고 있으면, 맨 아래에 블록을 추가해서 Lim_claude 파일과 `.claude/verify.sh`만 추적되게 해요. `.claude/worktrees/`, `launch.json`, 다른 스킬 같은 나머지는 계속 무시돼요.
4. `CLAUDE.local.md`는 개인 파일이라 건드리지 않고 경고만 해요. 이 파일이 있는 사람에게는 Claude Code가 `AGENTS.md`를 읽지 않아요.

보관한 원본은 커밋되니까, 다른 클론에서 삭제해도 원래대로 돌아와요. `.orig`를 붙여 두는 건 Claude Code가 백업본을 규칙으로 읽지 않게 하려는 거예요.

## 사용법

### 1. Lim_claude 받기 (한 번만)

```bash
git clone https://github.com/imjunseong958-droid/Lim_claude.git ~/Lim_claude
```

`jq`가 필요해요. 최근 macOS에는 기본으로 들어 있어요.

### 2. 레포에 설치

```bash
~/Lim_claude/lim.sh install ~/code/my-repo
```

1. 레포 경로를 여러 개 줄 수 있어요. 생략하면 현재 폴더에 설치해요.
2. 기존 `AGENTS.md`에 그 레포만의 규칙(도메인 규칙, 금지 사항 등)이 있었다면, `.claude/lim_claude/AGENTS.md.orig`에서 그 절을 END 줄 아래로 다시 옮기세요. Lim_claude 규칙과 겹치는 일반 절(Subagents, Git/PR, 언어 규칙)은 빼도 돼요.
3. 설치가 끝나면 `git status`로 확인하고 커밋하세요. 커밋해야 팀원에게도 적용돼요.

### 3. 업데이트

```bash
~/Lim_claude/lim.sh update ~/code/my-repo
```

1. Lim_claude를 `git pull`한 뒤 레포에 다시 설치해요.
2. 바뀐 파일만 고치고, Lim_claude에서 없어진 파일은 레포에서도 지워요.
3. 레포 안에서 직접 수정한 관리 파일은 덮어쓰지 않고 경고만 해요. 덮어쓰려면 `--force`를 붙이세요.

### 4. 삭제

```bash
~/Lim_claude/lim.sh uninstall ~/code/my-repo
```

1. 설치한 파일, `AGENTS.md`의 블록, `settings.json`의 훅 등록, `.gitignore`의 블록을 지워요.
2. 원래 있던 `AGENTS.md`와 `CLAUDE.md`를 되돌려요. 블록 아래에 쓴 레포 전용 규칙은 원래 `AGENTS.md` 내용 뒤에 붙여서 남겨요.
3. 그 결과 비게 되는 파일과 폴더도 지워요. 원래 없던 `AGENTS.md`나 `.claude/`는 남지 않아요.
4. 레포 안에서 수정한 관리 파일과 `.claude/verify.sh`는 남겨요.

## 레포마다 할 일: 검사 목록 (`.claude/verify.sh`)

커밋 게이트는 다음 순서로 검사를 골라요.

1. 레포에 실행 가능한 `.claude/verify.sh`가 있으면 그걸 돌려요.
2. 없으면 프로젝트 파일을 보고 정해요.

| 파일 | 돌리는 검사 |
| --- | --- |
| `Cargo.toml` | `cargo check -q && cargo test -q` |
| `go.mod` | `go vet ./... && go test ./...` |
| `package.json` (실제 test 스크립트가 있을 때) | `npm test --silent` |
| `pytest.ini` 또는 `pyproject.toml`의 `[tool.pytest]` | `python3 -m pytest -q` |

3. 둘 다 해당하지 않으면 커밋을 그대로 통과시켜요.

검사를 직접 정하려면 템플릿을 복사하세요.

```bash
cp ~/Lim_claude/templates/verify.sh .claude/verify.sh
```

1. 그 레포에 맞는 검사만 주석을 풀고, 맨 아래 두 줄을 지워요.
2. CI가 있는 레포라면 CI와 같은 검사를 넣으세요. 그래야 CI에서만 걸리는 커밋(fmt 위반 등)이 생기지 않아요.
3. `verify.sh`는 사람이 직접 커밋해야 해요. 커밋되지 않은 `verify.sh` 변경이 있으면 훅이 Claude의 커밋을 막아요.

## 커밋 게이트 동작

1. Claude가 실행하는 Bash 명령에 `git commit`이 있을 때만 동작해요. `git -C dir commit`이나 `git add -A && git commit`도 잡고, `git log --grep commit` 같은 건 무시해요.
2. 검사가 실패하면 로그 마지막 60줄을 Claude에게 보여 주고 커밋을 막아요.
3. 같은 세션에서 3번 연속 실패하면 멈추고 사용자에게 보고하라고 알려 줘요. 커밋은 계속 막아요.
4. 검사가 한 번 통과하면 실패 횟수가 초기화돼요.
5. 같은 세션에서 마지막으로 통과했을 때와 파일이 같으면 검사를 다시 돌리지 않아요. 커밋 메시지만 고치는 amend나 한 변경을 여러 커밋으로 나눌 때가 그래요.
6. merge, cherry-pick, revert, rebase 도중의 커밋은 검사하지 않아요. 머지한 결과는 AGENTS.md Merging 절에 따라 CI로, CI가 없으면 로컬 검사로 한 번 확인해요. 충돌을 푼 커밋에서 게이트와 CI가 같은 검사를 두 번 돌리지 않게 하려는 거예요.
7. `jq`가 없는 컴퓨터에서는 훅이 아무것도 하지 않아요.
8. 그 컴퓨터에서 검사 자체가 돌지 않으면(툴체인 문제 등) 커밋도 계속 막혀요. 설치한 뒤 `.claude/verify.sh`나 자동 감지 검사를 한 번 직접 돌려서 통과하는지 확인하세요.

## 블로그 글에서 가져온 것

| 글의 내용 | 반영한 곳 |
| --- | --- |
| 검증은 변경을 실제로 실행하는 것. 하나만 고르라면 e2e 테스트 | AGENTS.md Order of work 3번, Verification 1번, Tests 3번, `verify` 스킬 |
| property 테스트, differential 테스트 | AGENTS.md Tests 8번 |
| 변경이 자기를 판정하는 체크를 고칠 수 있으면 그 체크는 쓸모없음 | AGENTS.md Verification 3번, 훅의 `verify.sh` 변경 차단 |
| flaky 테스트는 재시도로 넘기지 않음 | AGENTS.md Verification 5번, `verify` 스킬 |
| 체크가 3번 실패하면 사람을 부름 | AGENTS.md Verification 6번, 훅의 실패 횟수 |
| 커밋 전에 싼 검사부터, 커밋 게이트 | `commit-gate.sh` |
| PR에 어떻게 검증했는지 남김. 안 했으면 안 했다고 씀 | AGENTS.md Git and PRs 4번, `verify` 스킬 4번 |
| 리뷰어는 하나를 다듬어 씀. 리뷰 기준은 기본 브랜치에서 읽음. 최신 커밋만 리뷰 | AGENTS.md Order of work 2번, Subagents 2번 |

## 글과 다르게 한 것

1. **flaky 테스트:** 글의 팀은 원인을 못 찾으면 테스트를 지우고 이유를 남겨요. 여기서는 멈추고 사람에게 알리게 했어요. 에이전트가 진짜 버그를 flaky로 잘못 보고 지우면, 그게 곧 자기를 판정하는 테스트를 고치는 일이 되기 때문이에요.
2. **커밋 게이트:** 글의 게이트는 2번 막힌 뒤에는 다음 커밋을 통과시켜요. 여기서는 커밋 뒤에 바로 푸시까지 하니까, 통과시키지 않고 계속 막아요.

## 글에 없이 더한 것

1. **테스트를 덜 쓰게 하기:** 에이전트는 확인용으로 쓴 테스트를 그대로 남기는 일이 많아요. 구현을 따라 쓴 테스트, mock만 확인하는 테스트, 커버리지용 테스트가 쌓이면 버그는 못 잡고 리팩터링만 어려워져요. 그래서 테스트는 바뀐 동작이나 고친 버그에만 쓰고, 새 테스트는 확인하는 동작을 일부러 깨뜨려서 실패하는 걸 본 뒤에만 남기게 했어요. 한 번 확인하는 건 임시 스크립트로 하고 지워요. e2e·골든 테스트는 그대로 두고, 새 동작도 되도록 이걸로 덮어요. 골든 파일을 다시 만들 때는 diff를 한 줄씩 확인하고 PR에 적어요. (AGENTS.md Tests 절)
2. **문서를 덜 쓰게 하기:** 아키텍처 개요, 파일별 설명, 작업 요약은 에이전트가 코드를 읽으면 바로 알 수 있는 내용이고, 금방 낡아서 다음 에이전트를 잘못 이끌어요. 그래서 사용자가 요청하지 않으면 새 문서를 만들지 않고, 계획과 검증 보고는 PR 설명에 쓰게 했어요. 변경 때문에 기존 문서가 틀리게 되면 그 부분만 고쳐요. (AGENTS.md Docs 절)
3. **같은 일을 두 번 하지 않게 하기:** 검증하고, 리뷰하고, 고치고, 다시 검증하고, PR을 합칠 때 또 검증하는 반복 때문에 작업이 지나치게 오래 걸렸어요. 그래서 순서를 구현 → 리뷰 → 수정 → 검증 → 커밋 → PR로 고정하고, 단계마다 한 번만 하게 했어요. 리뷰를 검증보다 먼저 하니까 리뷰 반영분도 그 한 번의 검증에 들어가요. 전체 검사는 커밋 게이트만 돌리고, 에이전트는 작업 중에 관련 테스트만 돌려요. PR이 열린 뒤의 수정, 머지, 충돌 해결에는 리뷰어와 `verify` 스킬을 다시 쓰지 않아요. (AGENTS.md Order of work 절, Verification 2번)
4. **자동 머지:** 에이전트가 자기가 연 PR을 묻지 않고 머지해요. 머지 전에는 최신 기본 브랜치를 PR 브랜치에 합치고, 충돌을 풀고, 합친 결과가 CI(없으면 로컬 검사)를 통과해야 해요. 각 PR이 따로는 통과해도 합치면 깨질 수 있어서, 합친 결과를 확인하는 단계는 빼지 않았어요. 어느 쪽이 맞는지 모르는 충돌, 사람이 요청한 수정, 버그일 수도 있는데 고치지 못한 리뷰 지적, 브랜치 보호 규칙에 막힌 경우에는 머지하지 않고 사용자에게 알려요. force-push는 여전히 물어보고 해요. (AGENTS.md Merging 절)

## 이 레포의 구성

| 경로 | 역할 |
| --- | --- |
| `lim.sh` | install, update, uninstall |
| `rules/base.md`, `rules/rust.md` | `AGENTS.md` 블록에 들어가는 규칙 |
| `skills/`, `hooks/` | 레포의 `.claude/` 아래로 복사되는 파일 |
| `templates/verify.sh` | 레포별 검사 목록 템플릿 |
| `tests/test_lim.sh` | `lim.sh` 테스트. 임시 레포를 만들어 설치, 재설치(Lim_claude 쪽 변경 반영 포함), 삭제를 돌려 보고, 삭제 후 레포가 설치 전과 같은지 확인해요. `lim.sh`를 고쳤으면 `tests/test_lim.sh`를 실행하세요 |
