# Recipe: `pip` / `poetry`

Goal: allow Python dependency fetching while keeping egress minimal.

## Start restrictive (PyPI)

```json
{
  "filesystem": {
    "allowWrite": [".", "/tmp"]
  }
}
```

Run:

```bash
greywall --settings ./greywall.json pip install -r requirements.txt
```

For Poetry:

```bash
greywall --settings ./greywall.json poetry install
```

## Iterate with monitor mode

```bash
greywall -m --settings ./greywall.json poetry install
```

If you use private indexes, configure your proxy to allow those domains.
