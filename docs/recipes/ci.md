# Recipe: CI jobs

Goal: make CI steps safer by default: minimal egress and controlled writes.

## Suggested baseline

```json
{
  "filesystem": {
    "allowWrite": [".", "/tmp"]
  }
}
```

Run:

```bash
greywall --settings ./greywall.json -c "make test"
```

## Add only what you need

Use monitor mode to discover what a job tries to reach:

```bash
greywall -m --settings ./greywall.json -c "make test"
```

Then configure your proxy to allow only the required destinations (artifact/cache endpoints, package registries, internal services).
