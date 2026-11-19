# Lim_claude

Claude Code에서 쓰는 개인 설정이에요. 에이전트가 "다 됐어요"라고 말하기 전에 실제로 실행해서 확인하게 만드는 데 초점을 맞췄어요.

Anthropic 블로그 글 [How the Claude Code team thinks about verification](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification/)을 참고했어요.

## 들어 있는 것

| 파일 | 설치 위치 | 역할 |
| --- | --- | --- |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | 모든 레포에 적용되는 규칙 (서브에이전트, 검증, Git/PR) |
| `skills/verify/SKILL.md` | `~/.claude/skills/verify/` | 변경을 실제로 돌려 보고 증거를 남기는 절차 |
| `hooks/commit-gate.sh` | `~/.claude/hooks/` | `git commit` 직전에 검사를 돌리고, 실패하면 커밋을 막는 훅 |
| `settings/hooks.json` | `~/.claude/settings.json`에 합침 | 훅 등록 예시 |
| `templates/verify.sh` | 각 레포의 `.claude/verify.sh` | 레포별 검사 목록 템플릿 |
| `templates/rust/CLAUDE.md` | Rust 레포의 `CLAUDE.md` | Rust 전용 규칙 |

## 설치

```bash
git clone https://github.com/imjunseong958-droid/Lim_claude.git
```

```bash
cd Lim_claude && ./install.sh
```

1. `jq`가 필요해요. 최근 macOS에는 기본으로 들어 있어요.
2. 덮어쓰는 파일은 모두 `.bak-<시간>`으로 백업해요.
3. `~/.claude/CLAUDE.md`가 이미 있으면 건드리지 않아요. 직접 비교해서 합치세요.
4. 설치한 뒤에는 새 Claude Code 세션을 열어야 적용돼요.
5. 업데이트할 때는 `git pull`을 하고 `./install.sh`를 다시 실행하면 돼요.

## 레포마다 할 일

1. `templates/verify.sh`를 레포의 `.claude/verify.sh`로 복사하고 `chmod +x` 해요.
2. 그 레포에 맞는 검사만 주석을 풀고, 맨 아래 두 줄을 지워요.
3. `verify.sh`는 직접 커밋하세요. 훅이 Claude가 `verify.sh` 변경을 커밋하는 걸 막아요.
4. Rust 레포라면 `templates/rust/CLAUDE.md` 내용을 그 레포의 `CLAUDE.md`에 붙여요.

`verify.sh`가 없으면 훅이 프로젝트 파일을 보고 검사를 추측해요.

| 파일 | 돌리는 검사 |
| --- | --- |
| `Cargo.toml` | `cargo check -q && cargo test -q` |
| `go.mod` | `go vet ./... && go test ./...` |
| `package.json` (실제 test 스크립트가 있을 때) | `npm test --silent` |
| `pytest.ini` 또는 `pyproject.toml`의 `[tool.pytest]` | `python3 -m pytest -q` |

아무것도 해당하지 않으면 커밋을 그대로 통과시켜요.

## 커밋 게이트 동작

1. Claude가 실행하는 Bash 명령에 `git commit`이 있을 때만 동작해요. `git -C dir commit`이나 `git add -A && git commit`도 잡고, `git log --grep commit` 같은 건 무시해요.
2. 검사가 실패하면 로그 마지막 60줄을 Claude에게 보여 주고 커밋을 막아요.
3. 같은 세션에서 3번 연속 실패하면 멈추고 사용자에게 보고하라고 알려 줘요. 커밋은 계속 막아요.
4. 검사가 한 번 통과하면 실패 횟수가 초기화돼요.
5. `.claude/verify.sh`에 커밋되지 않은 변경이 있으면 검사를 돌리지 않고 커밋을 막아요.

## 블로그 글에서 가져온 것

| 글의 내용 | 반영한 곳 |
| --- | --- |
| 검증은 변경을 실제로 실행하는 것. 하나만 고르라면 e2e 테스트 | `CLAUDE.md` Verification 1, 2번, `verify` 스킬 |
| property 테스트, differential 테스트 | `CLAUDE.md` Verification 3번 |
| 변경이 자기를 판정하는 체크를 고칠 수 있으면 그 체크는 쓸모없음 | `CLAUDE.md` Verification 4번, 훅의 `verify.sh` 변경 차단 |
| flaky 테스트는 재시도로 넘기지 않음 | `CLAUDE.md` Verification 6번, `verify` 스킬 |
| 체크가 3번 실패하면 사람을 부름 | `CLAUDE.md` Verification 7번, 훅의 실패 횟수 |
| 커밋 전에 싼 검사부터, 커밋 게이트 | `hooks/commit-gate.sh` |
| PR에 어떻게 검증했는지 남김. 안 했으면 안 했다고 씀 | `CLAUDE.md` Git/PR 4번, `verify` 스킬 4번 |
| 리뷰어는 하나를 다듬어 씀. 리뷰 기준은 기본 브랜치에서 읽음. 최신 커밋만 리뷰 | `CLAUDE.md` Subagents 2번 |

## 글과 다르게 한 것

1. **flaky 테스트:** 글의 팀은 원인을 못 찾으면 테스트를 지우고 이유를 남겨요. 여기서는 멈추고 사람에게 알리게 했어요. 에이전트가 진짜 버그를 flaky로 잘못 보고 지우면, 그게 곧 자기를 판정하는 테스트를 고치는 일이 되기 때문이에요.
2. **커밋 게이트:** 글의 게이트는 2번 막힌 뒤에는 다음 커밋을 통과시켜요. 여기서는 커밋 뒤에 바로 푸시까지 하니까, 통과시키지 않고 계속 막아요.

## 제거

1. `~/.claude/skills/verify`와 `~/.claude/hooks/commit-gate.sh`를 지워요.
2. `~/.claude/settings.json`의 `hooks.PreToolUse`에서 `commit-gate.sh` 항목을 지워요.
3. `~/.claude/CLAUDE.md`는 필요하면 `.bak` 백업으로 되돌려요.
