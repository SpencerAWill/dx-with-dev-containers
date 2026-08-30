// Metro defaults to resolving modules from the project directory only. In this
// pnpm workspace, dependencies also live in the repo-root node_modules, so point
// Metro at both and have it watch the workspace.
//
// Note: do NOT set resolver.disableHierarchicalLookup here. pnpm links packages
// through node_modules/.pnpm, and Metro reaches those by walking up from the
// importing file — which that flag turns off. It breaks packages that import
// undeclared dependencies (expo-router -> @expo/metro-runtime, for one).
const path = require("path");
const { getDefaultConfig } = require("expo/metro-config");

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, "../..");

const config = getDefaultConfig(projectRoot);

config.watchFolders = [workspaceRoot];
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, "node_modules"),
  path.resolve(workspaceRoot, "node_modules"),
];

module.exports = config;
