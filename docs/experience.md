# Greywall Development Notes

Lessons learned and issues encountered during development.

---

## strace log hidden by tmpfs mount ordering

**Problem:** Learning mode strace log was always empty ("No additional write paths discovered"). The log file was bind-mounted into `/tmp/greywall-strace-*.log` inside the sandbox, but `--tmpfs /tmp` was declared later in the bwrap args, creating a fresh tmpfs that hid the bind-mount.

**Fix:** Move the strace log bind-mount to AFTER `--tmpfs /tmp` in the bwrap argument list. Later mounts override earlier ones for the same path.

---

## strace -f hangs on long-lived child processes

**Problem:** `greywall --learning -- opencode` would hang after exiting opencode. `strace -f` follows forked children and waits for ALL of them to exit. Apps like opencode spawn LSP servers, file watchers, etc. that outlive the main process.

**Approach 1 - Attach via strace -p:** Run the command in the background, attach strace with `-p PID`. Failed because bwrap restricts `ptrace(PTRACE_SEIZE)` — ptrace only works parent-to-child, not for attaching to arbitrary processes.

**Approach 2 - Background monitor:** Run `strace -- command &` and spawn a monitor subshell that polls `/proc/STRACE_PID/task/STRACE_PID/children`. When strace's direct child (the main command) exits, the children file becomes empty — grandchildren are reparented to PID 1, not strace. Monitor then kills strace.

**Fix:** Approach 2 with two additional fixes:
- Added `-I2` flag to strace. Default `-I3` (used when `-o FILE PROG`) blocks all fatal signals, so the monitor's `kill` was silently ignored.
- Added `kill -TERM -1` after strace exits to clean up orphaned processes. Without this, orphans inherit stdout/stderr pipe FDs, and Go's `cmd.Wait()` blocks until they close.

---

## UDP DNS doesn't work through tun2socks

**Problem:** DNS resolution failed inside the sandbox. The socat DNS relay converted UDP DNS queries to UDP and sent them to 1.1.1.1:53 through tun2socks, but tun2socks (v2.5.2) doesn't reliably handle UDP DNS forwarding through SOCKS5.

**Approach 1 - UDP-to-TCP relay with socat:** Can't work because TCP DNS requires a 2-byte length prefix (RFC 1035 section 4.2.2) that socat can't add.

**Approach 2 - Embed a Go DNS relay binary:** Would work but adds build complexity for a simple problem.

**Fix:** Set resolv.conf to `nameserver 1.1.1.1` with `options use-vc` instead of pointing at a local relay. `use-vc` forces the resolver to use TCP, which tun2socks handles natively. Supported by glibc, Go 1.21+, and c-ares. Removed the broken socat UDP relay entirely.

---

## DNS relay protocol mismatch (original bug)

**Problem:** The original DNS relay used `socat UDP4-RECVFROM:53,fork TCP:1.1.1.1:53` — converting UDP DNS to TCP. This silently fails because TCP DNS requires a 2-byte big-endian length prefix per RFC 1035 section 4.2.2 that raw UDP DNS packets don't have. The DNS server receives a malformed TCP stream and drops it.

**Fix:** Superseded by the `options use-vc` approach above.

---

## strace captures directory traversals as file reads

**Problem:** Learning mode listed `/`, `/home`, `/home/user`, `/home/user/.cache` etc. as "read" paths. These are `openat(O_RDONLY|O_DIRECTORY)` calls used for `readdir()` traversal, not meaningful file reads.

**Fix:** Filter out `openat` calls containing `O_DIRECTORY` in `extractReadPath()`.

---

## SOCKS5 proxy credentials and protocol

**Problem:** DNS resolution through the SOCKS5 proxy failed with authentication errors. Two issues: wrong credentials (`x:x` vs `proxy:proxy`) and wrong protocol (`socks5://` vs `socks5h://`).

**Key distinction:** `socks5://` resolves DNS locally then sends the IP to the proxy. `socks5h://` sends the hostname to the proxy for remote DNS resolution. With tun2socks, the distinction matters less (tun2socks intercepts at IP level), but using `socks5h://` is still correct for the proxy bridge configuration.

---

## gost SOCKS5 requires authentication flow

**Problem:** gost's SOCKS5 server always selects authentication method 0x02 (username/password), even when no real credentials are needed. Clients that only offer method 0x00 (no auth) get rejected.

**Fix:** Always include credentials in the proxy URL (e.g., `proxy:proxy@`). In tun2socks proxy URL construction, include `userinfo` so tun2socks offers both auth methods during SOCKS5 negotiation.

---

## Network namespaces fail on Ubuntu 24.04 (`RTM_NEWADDR: Operation not permitted`)

**Problem:** On Ubuntu 24.04 (tested in a KVM guest with bridged virtio/virbr0), `--version` reports `bwrap(no-netns)` and transparent proxy is unavailable. `kernel.unprivileged_userns_clone=1` is set, bwrap and socat are installed, but `bwrap --unshare-net` fails with:
```
bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
```

**Cause:** Ubuntu 24.04 introduced `kernel.apparmor_restrict_unprivileged_userns` (default: 1). This strips capabilities like `CAP_NET_ADMIN` from processes inside unprivileged user namespaces, even without a bwrap-specific AppArmor profile. Bubblewrap creates the network namespace successfully but cannot configure the loopback interface (adding 127.0.0.1 via netlink RTM_NEWADDR requires `CAP_NET_ADMIN`). Not a hypervisor issue — happens on bare metal Ubuntu 24.04 too.

**Diagnosis:**
```bash
sysctl kernel.apparmor_restrict_unprivileged_userns  # likely returns 1
bwrap --unshare-net --ro-bind / / -- /bin/true        # reproduces the error
```

**Fix:** Disable the restriction (requires root on the guest):
```bash
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
# Persist across reboots:
echo 'kernel.apparmor_restrict_unprivileged_userns=0' | sudo tee /etc/sysctl.d/99-greywall-userns.conf
```

**Alternative:** Accept the limitation — greywall still works for filesystem sandboxing, seccomp, and Landlock. Network access is blocked outright rather than redirected through a proxy.

---

## Linux: symlinked system dirs invisible after `--tmpfs /`

**Problem:** On merged-usr distros (Arch, Fedora, modern Ubuntu), `/bin`, `/sbin`, `/lib`, `/lib64` are symlinks (e.g., `/bin -> usr/bin`). When switching from `--ro-bind / /` to `--tmpfs /` for deny-by-default isolation, these symlinks don't exist in the empty root. The `canMountOver()` helper explicitly rejects symlinks, so `--ro-bind /bin /bin` was silently skipped. Result: `execvp /usr/bin/bash: No such file or directory` — bash exists at `/usr/bin/bash` but the dynamic linker at `/lib64/ld-linux-x86-64.so.2` can't be found because `/lib64` is missing.

**Diagnosis:** The error message is misleading. `execvp` reports "No such file or directory" both when the binary is missing and when the ELF interpreter (dynamic linker) is missing. The actual binary `/usr/bin/bash` existed via the `/usr` bind-mount, but the symlink `/lib64 -> usr/lib` was gone.

**Fix:** Check each system path with `isSymlink()` before mounting. Symlinks get `--symlink <target> <path>` (bwrap recreates the symlink inside the sandbox); real directories get `--ro-bind`. On Arch: `--symlink usr/bin /bin`, `--symlink usr/bin /sbin`, `--symlink usr/lib /lib`, `--symlink usr/lib /lib64`.

---

## Linux: Landlock denies reads on bind-mounted /dev/null

**Problem:** To mask `.env` files inside CWD, the initial approach used `--ro-bind /dev/null <cwd>/.env`. Inside the sandbox, `.env` appeared as a character device (bind mounts preserve file type). Landlock's `LANDLOCK_ACCESS_FS_READ_FILE` right only covers regular files, not character devices. Result: `cat .env` returned "Permission denied" instead of empty content.

**Fix:** Use an empty regular file (`/tmp/greywall/empty`, 0 bytes, mode 0444) as the mask source instead of `/dev/null`. Landlock sees a regular file and allows the read. The file is created once in a fixed location under the greywall temp dir.

---

## Linux: mandatory deny paths override sensitive file masks

**Problem:** In deny-by-default mode, `buildDenyByDefaultMounts()` correctly masked `.env` with `--ro-bind /tmp/greywall/empty <cwd>/.env`. But later in `WrapCommandLinuxWithOptions()`, the mandatory deny paths section called `getMandatoryDenyPaths()` which included `.env` files (added for write protection). It then applied `--ro-bind <cwd>/.env <cwd>/.env`, binding the real file over the empty mask. bwrap applies mounts in order, so the later ro-bind undid the masking.

**Fix:** Track paths already masked by `buildDenyByDefaultMounts()` in a set. Skip those paths in the mandatory deny section to preserve the empty-file overlay.
