# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository status

This repository (`samyamit-dotcom/linux`) is currently a bare scaffold: it contains only a `README.md` (a single line, `# LINUX`) and no source code, build configuration, tests, or dependency manifests of any kind.

There is no existing architecture, build system, lint setup, or test suite to document. Do not assume this is a checkout of the upstream Linux kernel or any other specific project — despite the repo name, none of that source is present here.

## Working in this repository

- Before adding code, ask the user what the project is meant to be (e.g., a fresh application, a kernel module tree, documentation) if it isn't already clear from the current task/conversation.
- Once real source files, a build system, or tests are added, update this CLAUDE.md with the actual commands (build/lint/test) and a description of the real architecture — do not leave this placeholder in place once there's something to document.
