This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3010](http://localhost:3010) with your browser to see the result.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Features Implemented

local-postman is a local-first API client (a lightweight Postman). See `AGENTS.md` for the full feature/architecture breakdown. In short:

1. **Collections** of requests organized into groups (add / rename / delete).
2. **Environments** — color-coded variable profiles; the active environment substitutes `{{variables}}` into every request.
3. **Request builder** with Params / Headers / Body (JSON / Raw) tabs.
4. **Server proxy** (`/api/proxy`) so requests to any API work without CORS errors.
5. **Rich response viewer** (status / time / size, Pretty / Raw / Headers).
6. **Request history** — the last 50 sends, re-runnable.
7. **File-based storage** in `storage/*.json` and a three-mode theme (Dark Grey / Dark / Light).

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
