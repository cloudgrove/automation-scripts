#!/usr/bin/env node

'use strict';

const fs = require('node:fs');
const path = require('node:path');

const dependencySections = [
  'dependencies',
  'devDependencies',
  'optionalDependencies',
  'peerDependencies'
];

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function normalizePath(value) {
  return value.replaceAll(path.sep, '/').replace(/^\.\//, '').replace(/\/$/, '');
}

function isWithin(file, directory) {
  return file === directory || file.startsWith(`${directory}/`);
}

function workspacePatterns(packageJson) {
  if (Array.isArray(packageJson.workspaces)) {
    return packageJson.workspaces;
  }
  return packageJson.workspaces?.packages || [];
}

function expandWorkspacePattern(root, pattern) {
  const segments = normalizePath(pattern).split('/');
  const matches = [];

  function visit(directory, index) {
    if (index === segments.length) {
      if (fs.existsSync(path.join(directory, 'package.json'))) {
        matches.push(directory);
      }
      return;
    }

    const segment = segments[index];
    if (segment === '*') {
      if (!fs.existsSync(directory)) {
        return;
      }
      for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
        if (entry.isDirectory()) {
          visit(path.join(directory, entry.name), index + 1);
        }
      }
      return;
    }

    visit(path.join(directory, segment), index + 1);
  }

  visit(root, 0);
  return matches;
}

function findWorkspaceRoot(projectDir, source) {
  let directory = path.resolve(projectDir, source);
  const projectRoot = path.resolve(projectDir);

  while (isWithin(normalizePath(directory), normalizePath(projectRoot))) {
    const packageFile = path.join(directory, 'package.json');
    if (fs.existsSync(packageFile) && workspacePatterns(readJson(packageFile)).length > 0) {
      return directory;
    }
    if (directory === projectRoot) {
      break;
    }
    directory = path.dirname(directory);
  }

  throw new Error(`No npm workspace root found for ${source}`);
}

function loadWorkspaces(projectDir, roots) {
  const workspaces = new Map();

  for (const root of roots) {
    const rootPackage = readJson(path.join(root, 'package.json'));
    for (const pattern of workspacePatterns(rootPackage)) {
      for (const directory of expandWorkspacePattern(root, pattern)) {
        const packageJson = readJson(path.join(directory, 'package.json'));
        if (!packageJson.name) {
          throw new Error(`Workspace ${directory} has no package name`);
        }
        if (workspaces.has(packageJson.name)) {
          throw new Error(`Duplicate workspace package name: ${packageJson.name}`);
        }
        const dependencies = new Set();
        for (const section of dependencySections) {
          for (const dependency of Object.keys(packageJson[section] || {})) {
            dependencies.add(dependency);
          }
        }
        workspaces.set(packageJson.name, {
          dependencies,
          directory,
          repoPath: normalizePath(path.relative(projectDir, directory)),
          root
        });
      }
    }
  }

  return workspaces;
}

function findOwningWorkspace(file, workspaces) {
  return [...workspaces.entries()]
    .filter(([, workspace]) => isWithin(file, workspace.repoPath))
    .sort((left, right) => right[1].repoPath.length - left[1].repoPath.length)[0];
}

function selectAffectedFunctions({ changedFiles, configFile, functions, projectDir }) {
  const functionEntries = Object.entries(functions);
  if (functionEntries.length === 0 || changedFiles.length === 0) {
    return [];
  }

  const roots = new Set(functionEntries.map(([, entry]) => findWorkspaceRoot(projectDir, entry.source)));
  const workspaces = loadWorkspaces(projectDir, roots);
  const functionWorkspaces = new Map();

  for (const [functionId, entry] of functionEntries) {
    const source = normalizePath(entry.source || '');
    const owner = findOwningWorkspace(source, workspaces);
    if (!owner || owner[1].repoPath !== source) {
      throw new Error(`Lambda ${functionId} source must be an npm workspace: ${entry.source}`);
    }
    functionWorkspaces.set(functionId, owner[0]);
  }

  const globalInputs = new Set([normalizePath(path.relative(projectDir, configFile))]);
  for (const root of roots) {
    const rootPath = normalizePath(path.relative(projectDir, root));
    globalInputs.add(`${rootPath}/package.json`);
    globalInputs.add(`${rootPath}/package-lock.json`);
    globalInputs.add(`${rootPath}/npm-shrinkwrap.json`);
  }

  if (changedFiles.some(file => globalInputs.has(file))) {
    return functionEntries.map(([functionId]) => functionId).sort();
  }

  const affectedWorkspaces = new Set();
  for (const file of changedFiles) {
    const owner = findOwningWorkspace(file, workspaces);
    if (owner) {
      affectedWorkspaces.add(owner[0]);
    }
  }

  let changed = true;
  while (changed) {
    changed = false;
    for (const [name, workspace] of workspaces) {
      if (affectedWorkspaces.has(name)) {
        continue;
      }
      if ([...workspace.dependencies].some(dependency => affectedWorkspaces.has(dependency))) {
        affectedWorkspaces.add(name);
        changed = true;
      }
    }
  }

  return [...functionWorkspaces]
    .filter(([, workspaceName]) => affectedWorkspaces.has(workspaceName))
    .map(([functionId]) => functionId)
    .sort();
}

async function main() {
  const projectDir = process.env.PROJECT_DIR;
  const configFile = process.env.AWS_EDA_CONFIG_FILE;
  if (!projectDir || !configFile) {
    throw new Error('PROJECT_DIR and AWS_EDA_CONFIG_FILE are required');
  }

  let input = '';
  for await (const chunk of process.stdin) {
    input += chunk;
  }

  const functions = JSON.parse(input || '{}');
  const changedFiles = (process.env.AWS_EDA_CHANGED_FILES || '')
    .split('\n')
    .map(normalizePath)
    .filter(Boolean);

  for (const functionId of selectAffectedFunctions({
    changedFiles,
    configFile,
    functions,
    projectDir
  })) {
    console.log(functionId);
  }
}

main().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
