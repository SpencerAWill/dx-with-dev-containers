import path from "node:path";

/**
 * Runs against staged files only, on every commit, via .husky/pre-commit.
 *
 * Prettier is a real dependency here rather than an editor extension. That
 * distinction matters: an extension formats only for people who installed it
 * and configured it the same way, which is how a repo ends up with unrelated
 * whitespace churn in half its diffs.
 *
 * C# is deliberately not handled by Prettier — it has no C# parser. The .NET
 * side is formatted by `dotnet format`, which reads the same .editorconfig the
 * IDE does.
 */
export default {
  // Everything Prettier understands. --ignore-unknown means adding a new file
  // type never fails the commit just because Prettier has no parser for it.
  "*.{ts,tsx,js,jsx,mjs,cjs,json,jsonc,css,html,md,yml,yaml}": [
    "prettier --write --ignore-unknown",
  ],

  // ESLint only owns the web app; it is the only package with a config.
  "apps/web-app/**/*.{ts,tsx}": [
    "pnpm --filter web-app exec eslint --fix --no-warn-ignored",
  ],

  // `dotnet format` needs the solution plus an explicit include list.
  //
  // The paths MUST be relative to the working directory. Given absolute paths,
  // --include silently matches nothing: it reports "Formatted 0 of N files" and
  // exits 0, so the hook goes green while having done nothing. lint-staged
  // hands its functions absolute paths, hence the conversion below.
  "*.cs": (files) => {
    const relative = files.map((f) => path.relative(process.cwd(), f));
    return [
      `dotnet format SnapSort.slnx --no-restore --include ${relative.join(" ")}`,
    ];
  },
};
