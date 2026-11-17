# App Store files

| Folder | What it holds |
| --- | --- |
| `screenshots/iphone-6.9` | Six iPhone screenshots for App Store Connect, 1320 × 2868 (the 6.9-inch size; Apple scales them for smaller phones) |
| `screenshots/watch` | Five Apple Watch screenshots, 416 × 496 |
| `tools` | The script that makes the iPhone screenshots from the raw simulator screenshots |

To remake the iPhone screenshots after the app changes, download the raw screenshots from the `ci-results` branch and run:

```sh
node appstore/tools/render.js <folder with the raw screenshots> appstore/screenshots/iphone-6.9
```

It needs Node.js and Playwright (`npm install playwright`).

The privacy policy is [`PRIVACY.md`](../PRIVACY.md) and the support page is [`SUPPORT.md`](../SUPPORT.md). Their GitHub links go in the App Store Connect fields **Privacy Policy URL** and **Support URL**.
