# Recipe: `npm install`

Goal: allow npm to fetch packages, but block unexpected egress.

## Start restrictive

```json
{
  "filesystem": {
    "allowWrite": [".", "node_modules", "/tmp"]
  }
}
```

Run:

```bash
greywall --settings ./greywall.json npm install
```

## Iterate with monitor mode

If installs fail, run:

```bash
greywall -m --settings ./greywall.json npm install
```

Then configure your proxy to allow the minimum extra domains required for your workflow (private registries, GitHub tarballs, etc.).
