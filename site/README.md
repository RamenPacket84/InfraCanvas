# InfraCanvas Website Draft

This folder is a standalone static site draft for a future InfraCanvas-specific website.

## Review Locally

Open `site/index.html` in a browser.

## Deployment Direction

Good options for `infracanvas.com`:

1. Keep this folder in the InfraCanvas repo and configure Cloudflare Pages with `site` as the build output directory.
2. Move this folder into a dedicated `InfraCanvas-Site` repository and connect that repo to Cloudflare Pages.

The second option is cleaner if the website starts growing beyond a single product page. The first option is faster and keeps app and website changes together for now.

## Cloudflare Pages Settings

For GitHub-based deployment from this repo:

- Project name: `infracanvas`
- Production branch: `main`
- Framework preset: none
- Build command: `exit 0`
- Build output directory: `site`
- Root directory: leave unset

After the first deployment succeeds, add `infracanvas.com` as a custom domain in the Cloudflare Pages project.

## Current Links

- Download: `https://github.com/RamenPacket84/InfraCanvas/releases/download/v0.1.0/InfraCanvas-0.1.0.dmg`
- Source: `https://github.com/RamenPacket84/InfraCanvas`
- Docs: `https://github.com/RamenPacket84/InfraCanvas/wiki`
