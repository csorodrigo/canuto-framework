# Canuto release promotion

Current release: **v1.8.0**.

## Channels

- `main` is **edge**. A merge makes the change available only to callers that
  explicitly select `--channel edge` or pin that SHA.
- `releases/1.8.0` is the release branch for this version.
- `stable` is the default source used by the installer. It moves only after the
  release branch has passed the same final-SHA checks.

## Promotion order

1. Merge the reviewed PR into `main`.
2. Require the Ubuntu and macOS matrix, the complete framework suite, Skill
   Gardener suite, cross-consumer E2E, and vault integrity checks to pass on the
   merge SHA.
3. Create or fast-forward `releases/1.8.0` to that exact SHA.
4. Require the release-branch matrix to pass.
5. Fast-forward `stable` to the same SHA. Never promote a different rebuild.
6. Require the stable-branch matrix to pass and record the SHA in the release
   notes.

## Pinning and rollback

```bash
bash install.sh --update                    # stable
bash install.sh --update --channel edge     # main
bash install.sh --update --version 1.8.0    # releases/1.8.0
bash install.sh --update --ref <commit-sha> # strongest pin
bash install.sh --rollback <version>        # explicit release rollback
```

Branches are movable Git refs. The exact SHA is the strongest provenance.
`canuto-update-all.sh` therefore runs the complete `--check` before reporting a
consumer as current, even when its version and source-ref receipt already match.

## Failure policy

- A failed platform, consumer, reference, orphan, or source-receipt check blocks
  promotion.
- Do not force-update `stable` over a non-fast-forward history.
- Do not describe a release as promoted until `main`, the release branch, and
  `stable` all point to the same green SHA.
