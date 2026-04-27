# 🏷️ Automatic PR Labeling System

This repository uses an automatic labeling system that applies labels to pull requests based on branch naming conventions.

## 🎯 How It Works

When you create a PR, the system analyzes your branch name and automatically applies appropriate labels. This helps with:

- **Organization**: Quickly identify the type of changes in a PR
- **Release Management**: Automatic version bumping based on change types
- **Workflow Automation**: Trigger different actions based on label types

## 🌳 Branch Naming Conventions

### User-Specific Patterns
Perfect for your personal workflow:

```
jp/b/fix-login-bug          → 🐛 bug
jp/f/add-dark-mode          → ✨ feature
jp/d/update-readme          → 📚 docs
jp/c/cleanup-old-code       → 🧹 chore
jp/fix/authentication      → 🐛 bug
jp/feat/new-dashboard       → ✨ feature
jp/refactor/api-client      → ♻️ refactor
jp/test/add-unit-tests      → 🧪 test
jp/perf/optimize-queries    → ⚡ performance
jp/security/fix-xss         → 🔒 security
```

### Standard Patterns
Also supports conventional naming:

```
bug/fix-memory-leak         → 🐛 bug
feature/user-profiles       → ✨ feature
docs/api-documentation      → 📚 docs
chore/update-dependencies   → 🧹 chore
refactor/clean-components   → ♻️ refactor
test/integration-tests      → 🧪 test
perf/lazy-loading          → ⚡ performance
security/auth-improvements  → 🔒 security
hotfix/critical-bug        → 🚨 hotfix + 🐛 bug
release/v2.0.0             → 🚀 release
dependabot/npm/...         → 📦 dependencies
```

### Content-Based Detection
Smart detection based on branch content:

```
ci-pipeline-fix            → 🔧 ci/cd
config-updates             → ⚙️ config
style-improvements         → 🎨 style
api-endpoint-changes       → 🔌 api
database-migration         → 🗄️ database
```

## 🏷️ Available Labels

| Label | Color | Description |
|-------|--------|-------------|
| 🐛 bug | ![#dc2626](https://img.shields.io/badge/-dc2626-dc2626) | Something isn't working |
| ✨ feature | ![#16a34a](https://img.shields.io/badge/-16a34a-16a34a) | New feature or enhancement |
| 📚 docs | ![#2563eb](https://img.shields.io/badge/-2563eb-2563eb) | Documentation updates |
| 🧹 chore | ![#6b7280](https://img.shields.io/badge/-6b7280-6b7280) | Maintenance tasks |
| ♻️ refactor | ![#eab308](https://img.shields.io/badge/-eab308-eab308) | Code refactoring |
| 🧪 test | ![#a855f7](https://img.shields.io/badge/-a855f7-a855f7) | Test-related changes |
| ⚡ performance | ![#f59e0b](https://img.shields.io/badge/-f59e0b-f59e0b) | Performance improvements |
| 🔒 security | ![#dc2626](https://img.shields.io/badge/-dc2626-dc2626) | Security-related changes |
| 🚨 hotfix | ![#dc2626](https://img.shields.io/badge/-dc2626-dc2626) | Critical bug fix |
| 🚀 release | ![#059669](https://img.shields.io/badge/-059669-059669) | Release preparation |
| 📦 dependencies | ![#0369a1](https://img.shields.io/badge/-0369a1-0369a1) | Dependency updates |
| 🔧 ci/cd | ![#7c3aed](https://img.shields.io/badge/-7c3aed-7c3aed) | CI/CD pipeline changes |
| ⚙️ config | ![#4b5563](https://img.shields.io/badge/-4b5563-4b5563) | Configuration changes |
| 🎨 style | ![#ec4899](https://img.shields.io/badge/-ec4899-ec4899) | UI/UX and styling |
| 🔌 api | ![#059669](https://img.shields.io/badge/-059669-059669) | API-related changes |
| 🗄️ database | ![#7c2d12](https://img.shields.io/badge/-7c2d12-7c2d12) | Database changes |

### Version Labels (Required for Release)
| Label | Color | Description |
|-------|--------|-------------|
| major | ![#d93f0b](https://img.shields.io/badge/-d93f0b-d93f0b) | Breaking changes (1.0.0 → 2.0.0) |
| minor | ![#fbca04](https://img.shields.io/badge/-fbca04-fbca04) | New features (1.0.0 → 1.1.0) |
| patch | ![#0e8a16](https://img.shields.io/badge/-0e8a16-0e8a16) | Bug fixes (1.0.0 → 1.0.1) |

## 🚀 Release Automation

The labeling system integrates with our release workflow:

1. **Auto-labeling** applies type labels based on branch names
2. **Version validation** ensures every PR has a version label (major/minor/patch)
3. **Smart suggestions** recommend version labels based on detected change types
4. **Automated releases** use labels to determine version bumps

## 🔧 Manual Override

You can always manually add, remove, or change labels on any PR. The automation is designed to be helpful, not restrictive.

## 🎯 Best Practices

1. **Use descriptive branch names** - they help with automatic labeling
2. **Follow the naming conventions** - especially the `user/type/description` pattern
3. **Add version labels** - required for releases (major/minor/patch)
4. **Review auto-applied labels** - make sure they're accurate
5. **Add additional labels** - if needed for better categorization

## 🛠️ Setup

The labeling system is automatically configured when you run the "Setup Repository Labels" workflow. It:

- Creates all standard labels with proper colors
- Updates existing labels to match the standard
- Ensures consistency across the repository

---

*This system is designed to make your workflow smoother while maintaining consistency across the project. If you have suggestions for improvements, please create an issue or PR!*
