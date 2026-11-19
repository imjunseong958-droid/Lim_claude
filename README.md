# Lim_claude

코딩 에이전트가 "다 됐어요"라고 말하기 전에 실제로 실행해서 확인하게 만드는 규칙과 도구예요. 레포 안에 설치하고 커밋하면 그 레포를 클론하는 사람 모두가 같은 규칙을 쓰게 돼요.

Anthropic 블로그 글 [How the Claude Code team thinks about verification](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification/)을 참고했어요.

## 레포에 설치되는 것

| 위치 | 내용 | 누가 쓰나 |
| --- | --- | --- |
| `AGENTS.md` | 검증, Git/PR, 서브에이전트 규칙. `Cargo.toml`이 있으면 Rust 규칙도 들어가요 | AGENTS.md를 읽는 모든 에이전트 |
| `.claude/skills/verify/SKILL.md` | 변경을 실제로 돌려 보고 증거를 남기는 절차 | Claude Code (`verify` 스킬), 다른 에이전트는 AGENTS.md가 이 파일을 가리켜요 |
| `.claude/hooks/commit-gate.sh` | `git commit` 직전에 검사를 돌리고 실패하면 커밋을 막는 훅 | Claude Code |
| `.claude/settings.json` | 위 훅 등록 한 줄 | Claude Code |
| `.claude/lim_claude.manifest` | 설치한 파일 목록. 업데이트와 삭제에 써요 | `lim.sh` |

`AGENTS.md`에는 표시된 블록으로만 들어가요. 블록 밖에 쓴 내용은 설치, 업데이트, 삭제 모두 건드리지 않아요.

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
2. 설치가 끝나면 `git status`로 확인하고 커밋하세요. 커밋해야 팀원에게도 적용돼요.

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

1. 설치한 파일, `AGENTS.md`의 블록, `settings.json`의 훅 등록을 지워요.
2. 그 결과 비게 되는 파일과 폴더도 지워요. 원래 없던 `AGENTS.md`나 `.claude/`는 남지 않아요.
3. 레포 안에서 수정한 관리 파일과 `.claude/verify.sh`는 남겨요.

## 레포마다 할 일

### 1. CLAUDE.md가 있는 레포

Claude Code는 레포에 `CLAUDE.md`가 없을 때만 `AGENTS.md`를 읽어요. `CLAUDE.md`가 있으면 그 파일에 `@AGENTS.md` 한 줄을 넣어 주세요. 설치할 때 이 경우를 감지해서 알려 줘요.

### 2. 검사 목록 (`.claude/verify.sh`)

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
2. `verify.sh`는 사람이 직접 커밋해야 해요. 커밋되지 않은 `verify.sh` 변경이 있으면 훅이 Claude의 커밋을 막아요.

## 커밋 게이트 동작

1. Claude가 실행하는 Bash 명령에 `git commit`이 있을 때만 동작해요. `git -C dir commit`이나 `git add -A && git commit`도 잡고, `git log --grep commit` 같은 건 무시해요.
2. 검사가 실패하면 로그 마지막 60줄을 Claude에게 보여 주고 커밋을 막아요.
3. 같은 세션에서 3번 연속 실패하면 멈추고 사용자에게 보고하라고 알려 줘요. 커밋은 계속 막아요.
4. 검사가 한 번 통과하면 실패 횟수가 초기화돼요.
5. `jq`가 없는 컴퓨터에서는 훅이 아무것도 하지 않아요.

## 블로그 글에서 가져온 것

| 글의 내용 | 반영한 곳 |
| --- | --- |
| 검증은 변경을 실제로 실행하는 것. 하나만 고르라면 e2e 테스트 | AGENTS.md Verification 1~3번, `verify` 스킬 |
| property 테스트, differential 테스트 | AGENTS.md Verification 4번 |
| 변경이 자기를 판정하는 체크를 고칠 수 있으면 그 체크는 쓸모없음 | AGENTS.md Verification 5번, 훅의 `verify.sh` 변경 차단 |
| flaky 테스트는 재시도로 넘기지 않음 | AGENTS.md Verification 7번, `verify` 스킬 |
| 체크가 3번 실패하면 사람을 부름 | AGENTS.md Verification 8번, 훅의 실패 횟수 |
| 커밋 전에 싼 검사부터, 커밋 게이트 | `commit-gate.sh` |
| PR에 어떻게 검증했는지 남김. 안 했으면 안 했다고 씀 | AGENTS.md Git and PRs 4번, `verify` 스킬 4번 |
| 리뷰어는 하나를 다듬어 씀. 리뷰 기준은 기본 브랜치에서 읽음. 최신 커밋만 리뷰 | AGENTS.md Subagents 2번 |

## 글과 다르게 한 것

1. **flaky 테스트:** 글의 팀은 원인을 못 찾으면 테스트를 지우고 이유를 남겨요. 여기서는 멈추고 사람에게 알리게 했어요. 에이전트가 진짜 버그를 flaky로 잘못 보고 지우면, 그게 곧 자기를 판정하는 테스트를 고치는 일이 되기 때문이에요.
2. **커밋 게이트:** 글의 게이트는 2번 막힌 뒤에는 다음 커밋을 통과시켜요. 여기서는 커밋 뒤에 바로 푸시까지 하니까, 통과시키지 않고 계속 막아요.

## 이 레포의 구성

| 경로 | 역할 |
| --- | --- |
| `lim.sh` | install, update, uninstall |
| `rules/base.md`, `rules/rust.md` | `AGENTS.md` 블록에 들어가는 규칙 |
| `skills/`, `hooks/` | 레포의 `.claude/` 아래로 복사되는 파일 |
| `templates/verify.sh` | 레포별 검사 목록 템플릿 |
