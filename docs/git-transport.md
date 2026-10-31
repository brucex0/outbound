# Git upload transport

## Verified workaround

- Bruce's Mac repeatedly failed SSH pushes with `pack has bad object` / `inflate returned -5` or `-3`. HTTPS also failed with broken pipes and a TLS `bad record mac` alert.
- Local `git fsck`, pack indexing, independent Python zlib/checksum validation, and a local push succeeded. Changing Git versions, packing settings, SSH ciphers, or SSH ports did not resolve the remote failure.
- Pacing SSH input to 4 KiB writes with a 10 ms pause successfully pushed the same pending history. The underlying cause remains unconfirmed; an active Cisco socket filter was present during diagnosis.
- `scripts/git-ssh-paced.py` applies that workaround without changing SSH authentication, host verification, encryption, or output. Upload throughput is limited to approximately 400 KiB/s. Python 3 is required.

## Enable for this repository

Run from the main checkout (the absolute script path must remain available):

```sh
git config --local core.sshCommand "python3 '$(git rev-parse --show-toplevel)/scripts/git-ssh-paced.py'"
git push origin main
```

The setting is local Git configuration, shared by this repository's worktrees; it is not installed automatically by cloning. It applies to SSH remotes only. No packing overrides or HTTPS buffer changes are required.

## Remove after the transport issue is resolved

```sh
git config --local --unset core.sshCommand
git push origin main
```

If corruption recurs, re-enable the workaround. Do not reset history, delete local objects, or disable security software as a Git repair step.
