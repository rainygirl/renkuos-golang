# RenkuOS/arm64용 Go

[English](README.md) | [한국어](README.ko.md)

`GOOS=haiku GOARCH=arm64`용으로 실제 동작하는 Go 1.27.4 툴체인입니다. RenkuOS
자체의 Go 포크인 [korli/go](https://github.com/korli/go)(`golang-1.27-haiku`
브랜치, HaikuPorts의 `dev-lang/golang` 레시피가 빌드하는 바로 그 소스)는
`haiku/amd64`만 지원합니다. 이 포트는 korli/go가 이미 쓰고 있는 libc 호출
방식(Go의 `darwin`/`solaris` 포트와 같은 방식으로, 원시 syscall 트랩 대신
libroot.so를 직접 호출)을 그대로 따라 arm64로 확장한 것입니다 — 새로운
접근을 쓴 게 아니라, 같은 방식을 두 번째 아키텍처에 채워 넣은 것입니다.

이 저장소는 arm64 전용/RenkuOS 전용 런타임·syscall 소스(`src/` — 표준
라이브러리 전체에서 `*haiku*`로 이름 붙은 모든 파일과, RenkuOS용으로 수정한
공유 파일 `runtime/tls_arm64.{h,s}` -- 아래 "시그널" 참고), 빌드된 툴체인을 RenkuOS `.hpkg`로 만드는
패키징 스크립트, 그리고 실제 서드파티 호환성 문제를 해결하는 로컬 Go
모듈 프록시 오버라이드로 구성되어 있습니다. 전체 Go 소스 트리가 아닙니다 —
다른 플랫폼 포트를 적용할 때와 똑같이, `korli/go` 체크아웃(또는 amd64용
파일이 필요 없다면 업스트림 Go) 위에 이 저장소의 파일들을 그대로 얹어서
사용합니다.

## 미리 빌드된 패키지 설치

RenkuOS arm64 이미지에서는 대부분 직접 빌드할 필요가 없습니다 — 패키징된
툴체인은 이 프로젝트 자체의 pkgman 저장소에 배포되어 있습니다:

```sh
pkgman add-repo https://pkgman.rainygirl.com/arm64   # 시스템당 한 번만
pkgman install golang_bin
```

`scripts/smoke-test-golang.sh`는 같은 머신에서 돌리는 간단한 설치 후
점검입니다 — 고루틴/뮤텍스 프로그램, `os/exec`, 그리고 `bin/go` 자신의
`GOPROXY`/`GONOSUMDB` 기본값을 통한 실제 서드파티 모듈 빌드까지, 이
패키지의 수정 사항이 건드린 바로 그 세 경로입니다.

```sh
sh scripts/smoke-test-golang.sh
```

## 빌드하기

```sh
git clone --branch golang-1.27-haiku https://github.com/korli/go.git go-haiku-arm64
# 이 저장소의 src/ 트리를 파일 단위로 그대로 덮어씁니다
cd go-haiku-arm64/src
GOOS=haiku GOARCH=arm64 GOROOT_BOOTSTRAP=/path/to/a/working/go ./make.bash
```

이러면 한 GOROOT 안에 툴체인이 두 개 생깁니다: 다른 곳에서 `haiku/arm64`
바이너리를 교차 빌드할 때 쓰는 호스트(예: `linux/arm64`)용 컴파일러, 그리고
RenkuOS 위에서 직접 실행하도록 만들어진 진짜 RenkuOS ELF 바이너리인 네이티브
`bin/haiku_arm64/go` — 단순 교차 빌드 타깃이 아니라 자가 호스팅 SDK입니다.
`scripts/cross-arm64-golang.sh`가 이 두 번째 것을 설치 가능한 `.hpkg`로
패키징합니다(`golang_bin.recipe` 참고). 이 스크립트는 이 포트의 RenkuOS
이미지 자체를 빌드할 때 쓰는 것과 같은 Docker 빌드 컨테이너 안에서,
빌드된 트리가 `GOROOT_SRC`에 있다고 가정하고 실행됩니다.

## 두 가지 런타임 버그

둘 다 추측이 아니라 실제로 재현 가능한, 결정적인 행(hang)을 통해 찾아낸
것이고, 이 트리에는 이미 수정되어 있습니다.

**1. 어셈블리 트램폴린 4곳의 32비트/64비트 반환값 너비 버그**
(`src/runtime/sys_haiku_arm64.s`의 `sem_wait_trampoline`,
`sem_timedwait_trampoline`, `pipe2_trampoline`, `fcntl_trampoline`).
각각 libc 호출의 반환값을 `CMP $0, R0; BGE ok`로 검사했는데, 이 호출들은
32비트 C `int`를 반환하고(오류 시 `-1`), AArch64는 32비트 레지스터 쓰기를
부호 확장이 아니라 **영 확장**합니다 — 그래서 진짜 `-1`이 64비트 `R0`에
`0x00000000FFFFFFFF`라는 큰 양수로 들어와 오류 분기를 절대 타지 않았습니다.
`err`는 항상 `0`으로 고정되어 `semasleep()`이 실제 타임아웃이나 시그널을
제대로 인식할 수 없었습니다. `CMPW $-1, R0; BNE ok`로 수정했습니다 — Go의
`darwin`/`openbsd` arm64 포트가 똑같은 위험에 이미 쓰고 있는 바로 그
방식입니다. `libroot.so`의 `sem_clockwait` 디스어셈블리(`mov w0, w19`,
32비트 쓰기)로 확인했습니다. 이 수정 하나만으로도 고루틴/뮤텍스를 쓰는
보통의 프로그램을 직접 컴파일해서 실행했을 때 안정적으로 정상 동작합니다.

**2. Go 자체의 시그널 처리가 `os/exec`와 실제 빌드를 멈추게 함**
(`src/runtime/signal_unix.go`, 리비전 9까지. 진짜 원인은 리비전 10에서 찾아
고쳤고 아래 두 우회책은 모두 없앴습니다 -- "시그널" 참고). Go는 SIGCHLD에 무조건 자체 트랩을
설치하는데, `asmcgocall`을 거쳐 libc 호출(막 fork한, 이미 종료된 자식에
대한 `read()`/`wait4()` — 모든 `os/exec.Cmd.Start()+Wait()`가 정확히 이
동작을 하며, `cmd/go`가 `compile`/`asm`/`link`를 띄우는 것도 포함됨) 안에
블록되어 있는 M에 유저스페이스 시그널 트랩이 떨어지면 해당 M이 EINTR
재시도 루프에서 계속 멈춰 있었습니다. 최소 재현 코드(`exec.Command
("/bin/sleep", "0")`)로 확인: Go의 핸들러가 설치된 상태에서는 반복
시도 중 80~100%가 행, `signal.Ignore(syscall.SIGCHLD)`로는 0%. RenkuOS에서는
SIGCHLD를 물려받은 기본 동작 그대로 두도록 수정했습니다
(`sigInstallGoHandler()`가 `GOOS == "haiku"`일 때 SIGCHLD에 대해 `false`
반환); 명시적으로 요청하는 프로그램은 `os/signal.Notify(syscall.SIGCHLD)`로
여전히 핸들러를 다시 설치할 수 있습니다. 똑같은 위험이 `sigPreempt`
(`SIGURG`)를 통해서도 다시 나타났습니다 — Go의 비동기 선점이 실행 중인
M에 10~20ms마다 이 시그널을 보내는데, 실제 빌드는 몇 초 동안 수십 번
fork+exec을 하므로 블록된 libc 호출 중에 떨어질 기회가 많습니다. RenkuOS에서
비동기 선점을 비활성화해 수정했습니다(`const preemptMSupported = GOOS !=
"haiku"` — Go 1.14가 비동기 선점을 도입하기 전까지 모든 Go 프로그램이
기본으로 받아들였던 것과 같은 트레이드오프이고, `os_plan9.go`/`os_wasm.go`도
각자의 이유로 이미 같은 선택을 하고 있습니다). 함수 호출 기반의 협조적
선점은 영향받지 않습니다. `go build std` — 표준 라이브러리 전체, 수백 개
패키지, 실제 fork/exec 다수 — 가 깨끗한 빌드 캐시에서 exit code 0으로
끝나는 것으로 끝까지 검증했습니다. 교차 빌드로도, 그리고 나중에는
셀프호스팅으로도 확인했습니다 — 실제로 이미 설치된 패키지 자신의
네이티브 `bin/haiku_arm64/go`가 실제 타깃 머신에서, 평범한 SSH로(데스크탑
세션 없이), 표준 라이브러리를 ~52초에 빌드했습니다. 이걸 여러 번
반복하다가 간헐적인 결함 하나를 발견했습니다(깨끗한 캐시로 시도한
대략 열두 번 중 한 번 실패, 에러 텍스트는 잡지 못했고, 메모리는 원인에서
제외했습니다 — 실패한 그 한 번도 여유 메모리가 8GiB 중 7.5GiB 아래로
내려간 적이 없습니다) — 아직 근본 원인은 못 찾았습니다. 그 직후 다섯 번을
더 포함해 다른 모든 시도는 전부 통과했습니다.

별개의 패키징 누락(`pkg/include/` — `textflag.h`, `funcdata.h`,
`asm_*.h` 헤더들이 `.hpkg`에 전혀 담기지 않아, 위 두 버그가 더 이상
가로막지 않는 순간 asm 기반 패키지가 `-gensymabis`에서 전부 실패하던
문제)은 `src/`가 아니라 `scripts/cross-arm64-golang.sh`에서 고쳤습니다.

## 시그널

리비전 9까지 haiku/arm64의 Go 프로그램은 SIGTERM, SIGINT, SIGHUP을
무시했고(`kill -9`로만 멈춤) `os/signal.Notify`로는 아무것도 받지 못했습니다.
Go가 핸들러를 설치한 시그널은 그것을 받은 스레드를 조용히 죽였습니다 --
`strace -T`로 보면 시그널은 도착하는데 그 스레드는 그 뒤로 시스템 콜을 한
번도 하지 않습니다. 위 버그 2의 SIGCHLD/SIGURG 행도 같은 원인이었습니다.
버그는 넷이었고 모두 리비전 10에서 고쳤습니다:

- **`sigtramp`의 프레임이 자기 복귀 주소를 덮어씀**
  (`src/runtime/sys_haiku_arm64.s`). `sys_haiku_amd64.s`를 본떠 인자를
  `0/8/16(SP)`에 저장했습니다. amd64에서는 빈 자리지만 arm64에서
  `0(RSP)`는 어셈블러 프롤로그가 함수 자신의 LR을 저장하는 곳이라,
  `MOVW R0, 0(RSP)`가 복귀 주소의 하위 32비트를 시그널 번호로 바꿔 버렸고
  `sigtramp`는 Haiku의 commpage 시그널 핸들러로 돌아가지 못했습니다. 이제
  다른 arm64 포트들처럼 프레임이 `8(RSP)`부터 시작합니다.
- **`sigtrampgo`를 잘못된 ABI로 호출** (같은 파일). 어셈블리에서 그냥
  `BL runtime·sigtrampgo(SB)`를 하면 ABI0 래퍼로 연결되는데, 이 래퍼는
  인자를 `8/16/24(RSP)`에서 읽습니다 -- 그래서 `sigtrampgo`는 `siginfo`
  포인터를 시그널 번호로 받았습니다. 이제 `sys_linux_arm64.s`/
  `sys_darwin_arm64.s`처럼 `<ABIInternal>` 진입점을 R0-R2 인자로
  호출합니다(`badsignal`도 같음).
- **`ucontext_t.uc_mcontext`의 오프셋은 40이 아니라 48**
  (`src/runtime/defs_haiku_arm64.go`). `struct vregs`에
  `__uint128_t fp_q[32]`가 있어 `mcontext_t`가 16바이트 정렬입니다(Haiku
  교차 gcc의 `offsetof`로 확인). 시그널 컨텍스트에서 읽는 레지스터가 전부 한
  칸씩 밀려 있었습니다: `sigsp()`는 LR을, `sigpc()`는 SP를 돌려줬습니다.
  비동기 선점은 안전 지점을 한 번도 찾지 못했고, 크래시 리포트의 PC도
  틀렸습니다.
- **`pthread_self()`가 32비트로 잘림** (`src/runtime/os2_haiku.go`).
  `int32`를 반환하는 `libcCall`을 거쳤기 때문에 `m.procid`가 부호 확장된
  반쪽 포인터였고, 비동기 선점의 SIGURG를 보내는 `pthread_kill`이 libroot
  안에서 폴트를 냈습니다. 이제 트램폴린이 인자로 받은 포인터에 `pthread_t`
  전체를 저장합니다.

또한 `g`를 R28에만 두지 않고 TLS에도 둡니다(`src/runtime/tls_arm64.h`,
`tls_arm64.s`): Haiku에서 TPIDR_EL0은 libroot 자체의 TLS 슬롯 배열을
가리키고, `g`는 haiku/amd64가 쓰는 것과 같은 62번 슬롯에 있습니다.
`sigtramp`가 거기서 `g`를 읽으므로, libroot 코드(여기서 R28은 그냥
callee-saved 레지스터 중 하나)를 실행하다 시그널을 받아도 올바른 `g`를
찾습니다 -- darwin과 openbsd가 늘 TLS에 `g`를 두는 것과 같은 이유입니다.

이것들을 고친 뒤 버그 2의 두 우회책을 없앴고 `signal_unix.go`는 다시
업스트림 그대로입니다: Go가 SIGCHLD 핸들러를 설치하고 비동기 선점도
켜져 있습니다. 시작할 때마다 stderr에 찍히던 디버그 출력(`234567`,
`runtime/asm_arm64.s`에 남아 있던 `dbgw` 호출)도 없앴고, 이 파일도 다시
업스트림 그대로입니다.

arm64 RenkuOS VM에서 확인: `signal.Notify`가 SIGTERM, SIGINT, SIGTERM을
연달아 받음; `Notify` 없이 SIGTERM은 상태 143, SIGINT는 130, SIGHUP은 129로
종료; nil 역참조가 panic으로 recover됨; 고루틴 셋이 계산하는 동안 초당 약
천 개의 SIGUSR1을 받음(계산 오류 없음); 고루틴 하나가 `for {}`로 도는
동안에도 GC 완료; `os/exec`로 자식 200개 연속 실행을 다섯 번; tailscaled가
SIGTERM으로 깔끔히 종료되고 서비스 스크립트의 정리 단계가 실행됨; rclone,
syncthing, gh가 SIGTERM/SIGINT로 종료. 설치한 리비전 10 패키지로 네이티브
실행: `scripts/smoke-test-golang.sh` 통과, `go test -short os/signal sync`는
`TestNotifyContextStringer`만 실패(Linux의 SIGTERM 이름 "terminated"를
기대하지만 Haiku는 "termination requested").

남은 문제: 깨끗한 캐시의 `go build std`가 29번 중 3번
`compile: exit status 255`로, 다른 출력 없이 실패했습니다. 비동기 선점을
켜도 꺼도 마찬가지입니다(버그 2에 적은 간헐적 결함). 크래시 출력이 있었더라도
보이지 않습니다: Haiku의 `issetugid()`(libbsd)는 항상 1을 반환하므로 Go
런타임이 모든 프로그램을 secure mode로 실행하고, 이 때문에 치명적 시그널
보고가 첫 줄만 남습니다(`SIGQUIT: quit`, 고루틴 덤프 없음).

## 서드파티 모듈 호환성 (`scripts/golang-goproxy-overrides/`)

표준 라이브러리의 빌드 태그 문제가 아니라 모듈 생태계 자체의 실제 공백입니다.
패키징된 `golang_bin`의 `bin/go`는 래퍼입니다(진짜 바이너리는
`bin/go-real`) — `GOPROXY`/`GOSUMDB` 기본값을 지정하고(이 툴체인은 둘 다
빈 값으로 배포되어 있었습니다), 실제 proxy보다 앞에 로컬 GOPROXY 프로토콜
디렉터리를 두어 패치된 모듈들을 같은 모듈 경로·버전으로 서빙합니다.
정확한 패치 내용과 같은 종류의 공백이 있는 다른 모듈로 확장하는 방법은
해당 디렉터리의 README를 참고하세요.

**`github.com/mattn/go-isatty`**(`github.com/gin-gonic/gin`의 기본
로거가 씀)는 OS별로 터미널 구현 파일을 하나씩 두고 있는데 `haiku`와 맞는
게 하나도 없어서, 이 모듈을 끌어오는 어떤 모듈이든 빌드 시점에
`IsTerminal`/`IsCygwinTerminal`이 `undefined`가 됩니다. 한 줄 패치로
고쳤습니다(기존에 있던 "지원 안 되는 플랫폼은 false 반환" 스텁에 `haiku`
추가). 모듈 캐시를 완전히 비운 상태에서 끝까지 검증했습니다: 새 `go mod
init`, `go get github.com/gin-gonic/gin`, `go build`, 실행, 그리고
`gin.Default()` 핸들러에 대한 실제 `curl` HTTP 200 — 수동 `replace`
지시어도, 미리 채워둔 캐시도 없이.

**`golang.org/x/sys`**는 어떤 배포 버전에도 `haiku` 지원이 전혀 없습니다 —
직접 클론해서 모든 버전의 `unix/*.go`에 `haiku`를 grep해봐도 일치하는 게
하나도 없는 걸로 확인했습니다. `golang.org/x/sys/unix`를 직접 임포트하는
모듈은(`golang.org/x/term`처럼 자체 안전한 폴백이 있어서 `haiku`에서
`x/sys/unix`에 실제로 닿지 않는 경우가 아니라면) 전부 빌드가 깨지는데,
이는 go-isatty의 공백보다 훨씬 더 큰, 생태계의 큰 부분입니다. 여기서
새로 패치한 게 아니라, `korli/go`의 자매 포크인
[korli/sys_haiku](https://github.com/korli/sys_haiku)(`master-haiku`
브랜치, 이 모듈의 실제 `amd64` 전용 Haiku 포트를 몇 년째 유지하고
있음)에서 가져오고, 거기에 이 포트 자신이 이미 갖고 있던 `arm64` 확장
파일들(이 저장소 자신의
`src/cmd/vendor/golang.org/x/sys/unix/*_arm64*`, 그대로 재사용)을 더해
깨끗한 `v0.50.0` 체크아웃 위에 적용했습니다. 교차 빌드만이 아니라 실제
타깃 머신에서 끝까지 검증했습니다: 패치된 트리로 빌드한 작은 프로그램을
SSH로 실제 머신에 복사해서 그 위에서 실행 — `unix.Stat`을 실제 경로에
대해, `Socket`/`Bind`/`Getsockname` 전체 라운드트립을, 그리고 (go-isatty
자신이 실제로 호출하는 것과 똑같은) tty가 아닌 fd에 대한
`IoctlGetTermios`를 — 전부 올바른 결과를 돌려줬고, 모듈 전체(`go build
./...`, Windows/Plan9를 뺀 모든 패키지)가 깨끗하게 빌드됩니다.

다만 이 오버라이드는 정확한 버전에만 걸려 있습니다 — 가정이 아니라 실제
한계입니다: `github.com/shirou/gopsutil/v3`는 자기 `go.mod`에 따라
`golang.org/x/sys v0.20.0`로 해석됐는데, 이 오버라이드가 아직 다루지
않는 버전이라 실제(패치 안 된) proxy로 떨어졌습니다. 같은
`unix.Stat`을 쓰는 프로그램을 `v0.50.0`(정상)과 `v0.20.0`
(`undefined: unix.Stat_t`)에 각각 빌드해봐서 이 버전 공백이 실제임을
직접 확인했습니다. 지금은 하나가 아니라 `v0.41.0`부터 `v0.50.0`까지
열 개 버전을 다루도록 넓혔는데, 도움은 되지만 공백을 완전히 없애지는
못합니다 — 자세한 내용과, 실제로는 이 경로를 전혀 타지 않은 두 개의
실제 서드파티 모듈(`fasthttp`, `gopsutil`) 이야기는
`scripts/golang-goproxy-overrides/README.md`를 참고하세요.

## cgo

`CGO_ENABLED=1`은 이걸 찾아서 고치기 전까지는 전혀 동작하지 않았습니다:
cgo 프로그램을 링크하면 무조건 `relocation R_AARCH64_ADR_PREL_PG_HI21
against symbol 'poll' which may bind externally ... recompile with
-fPIC`로 실패했습니다. `cmd/link/internal/ld/data.go`의 `dynreloc()`에서
근본 원인을 찾았습니다: Go는 외부 링킹(cgo가 항상 쓰는 방식)일 때는
항상 `FlagD`(동적 로더 형식 출력 억제)를 설정하는데, 그러면
`cgo_import_dynamic` 데이터 심볼의 주소 참조 relocation을 GOT 경유로
바꿔주는 `dynrelocsym()` 패스가 무조건 스킵됩니다. Haiku의 libc-call
방식 포트는 바로 이 재작성이 필요합니다 — 컴파일러가 런타임 자신의
`libc_poll`(`netpoll_haiku.go`) 같은 심볼의 주소를 그냥 페이지 상대
ADRP+ADD로 생성해두고, gcc/ld에 넘기기 전에 링커가 GOT 상대 주소로
바꿔주는 걸 전제하기 때문입니다 — 다른 플랫폼은 전부 이 재작성이
필요 없거나(syscall 기반 포트) 다른 방식으로 처리합니다. 처음 시도한
수정(Haiku에 한해 `FlagD` 자체를 건너뜀)은 진짜 `.dynsym`/`.hash`/
`.got.plt`까지 통째로 만들어버렸는데, 이건 평범한 외부 링크용 객체
파일을 만드는 것과 충돌해서 링커 자신의 객체 작성 코드가
`internal error: ElfShdr relocSect`로 죽었습니다. 실제로 동작하는
수정은 `FlagD`가 설정된 상태에서도 Haiku에 대해서만 그 `Textp`
relocation 재작성 루프 하나만 돌리고, `FlagD`가 원래 건너뛰던 나머지는
그대로 다 건너뛰는 것입니다. 끝까지 검증했습니다: 실제 C 함수를
호출하고 C 문자열을 Go로 다시 변환하는 cgo 프로그램(`C.add`,
`C.CString`/`C.GoString`)이 정상적으로 빌드되고 실행되며, 기존의
고루틴/`os/exec`/go-isatty 스모크 테스트와 전체 `go build std`도
회귀 없이 그대로 통과합니다.

### cgo에서의 g와 TLS

위 링크 수정으로 cgo 프로그램이 링크는 되었지만, 고루틴 포인터 `g`는
여전히 엉뚱한 곳에 저장되고 있었습니다. cgo가 켜지면 런타임은 `g`를
`TPIDR_EL0 + runtime.tls_g`에 저장하는데(`runtime/tls_arm64.s`),
`tls_g`가 ELF TLS 심볼이라 외부 링커가 이를 local-exec 오프셋 16으로
만들었습니다. Haiku에서 `TPIDR_EL0`는 ELF 스레드 포인터가 아니라
스레드별 TLS 슬롯 배열(libroot의 `tls_address()`)을 가리키고, 오프셋
16은 2번 슬롯 `TLS_ERRNO_SLOT`입니다. 즉 `g`와 `errno`가 같은 워드를
쓰고 있었습니다. 단순한 C 호출은 문제가 없었지만(`asmcgocall`이 `g`를
스택에서 복원), C 함수가 `errno`를 설정한 뒤 export된 Go 함수를
호출하거나 그 상태에서 시그널이 오면 잘못된 `g`를 읽어 프로그램이
멈췄습니다.

이제 `runtime/tls_arm64.h`가 haiku에서 `TLSG_IS_VARIABLE`를 정의하고
(Android와 같은 방식), `rt0_go`가 `_cgo_init`에 `&tls_g`를 넘기며,
`runtime/cgo/gcc_haiku_arm64.c`가 `tls_allocate()`로 받은 슬롯의 바이트
오프셋을 채웁니다. 슬롯 번호는 C가 만든 스레드를 포함해 모든 스레드에서
같습니다. cgo를 쓰지 않는 프로그램은 `tls_g`를 읽지 않습니다.

### cgo 프로그램 빌드

크로스 빌드(haiku-builder, sysroot = `haiku.hpkg` + `haiku_devel.hpkg` +
`gcc_syslibs`/`gcc_syslibs_devel`를 `<sysroot>/boot/system`에 풀어 둔 것):

```sh
X=/root/renku-arm64-work/generated.arm64/cross-tools-arm64/bin
CGO_ENABLED=1 GOOS=haiku GOARCH=arm64 \
  CC="$X/aarch64-unknown-haiku-gcc --sysroot=<sysroot>" \
  CXX="$X/aarch64-unknown-haiku-g++ --sysroot=<sysroot>" go build
```

RenkuOS에서 네이티브 빌드: arm64용 C 컴파일러가 아예 없었습니다(저장소에는
`gcc`가 아니라 `gcc_syslibs`만 있음). `scripts/cross-arm64-gcc.sh`가
이미지 자체의 크로스 툴로 gcc 13.3 + binutils 2.41을 캐나디안 크로스로
빌드해 `gcc` 패키지로 만듭니다(`/boot/system/develop/tools`에 설치되고
`gcc`/`g++`/`cc`/`ld` 등은 `/boot/system/bin`에 링크, `haiku_devel` 필요).
설치하면 `go env CGO_ENABLED`가 1이 되고 그냥 `go build`로 cgo가 쓰입니다.

참고:
- `github.com/mattn/go-sqlite3`는 그대로 동작합니다(내장 SQLite를
  컴파일). `-tags libsqlite3`에는 `#cgo haiku LDFLAGS`가 없으므로
  `CGO_LDFLAGS=-lsqlite3`를 주어야 하고, RENKU의 `sqlite3` 패키지에는
  라이브러리만 있고 `sqlite3.h`는 없습니다.
- C++(Be API) 코드는 패키지 안의 `extern "C"` 심과
  `#cgo LDFLAGS: -lbe -lstdc++`로 쓸 수 있습니다.

RenkuOS arm64(QEMU)에서 크로스/네이티브 빌드 모두 검증: C hello,
C에서 errno 설정 후 Go 호출(TLS 수정 전에는 멈춤), mattn/go-sqlite3 두
방식, Be API 심(`find_directory`, `get_system_info`, `BString`,
`be_roster`), 스트레스 테스트(고루틴 1000개 x C 호출 20000번, Go 스레드와
C pthread 16개에서의 Go 콜백, GC 부하) 10/10회.

## 라이선스

BSD 3-Clause, Go 자체와 같은 라이선스입니다 — 이 파일들은 Go 자체의
OS별 런타임·syscall 파일들과 나란히 놓이도록 쓴 플랫폼 포트 소스이며,
언젠가 korli/go나 Go 본체에 업스트림될 수 있기를 바랍니다.

## AI 사용 고지

이 작업은 Claude(Anthropic)가 다 했습니다. 런타임 포팅, 두 버그의 수정,
패키징, 검증까지 전부 에이전틱 코딩 세션 안에서 Claude가 작성하고
빌드하고 실행하고 디버깅했습니다. 작성자는 세션의 방향을 정하고 각 단계를
승인했습니다.
