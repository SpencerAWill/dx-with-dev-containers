import js from "@eslint/js";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import tseslint from "typescript-eslint";
import { defineConfig, globalIgnores } from "eslint/config";

export default defineConfig([
  globalIgnores(["dist"]),
  {
    files: ["**/*.{ts,tsx}"],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      globals: globals.browser,
    },
  },
  {
    // Route modules cannot satisfy react-refresh/only-export-components, and
    // the rule fired on every one of them.
    //
    // TanStack Router's file-based routing mandates the shape: the module
    // exports `Route = createFileRoute(...)` — a non-component — and hands its
    // component to that call rather than exporting it. The rule then reports
    // the unexported component. `allowExportNames: ["Route"]` does not help;
    // it permits the Route export but the component is still unexported, which
    // is what the rule objects to.
    //
    // The rule's premise does not hold here anyway: the TanStack Router Vite
    // plugin handles HMR for route modules, so Fast Refresh works despite the
    // shape. Off for routes only — everything under src/components keeps it.
    files: ["src/routes/**/*.tsx"],
    rules: {
      "react-refresh/only-export-components": "off",
    },
  },
]);
