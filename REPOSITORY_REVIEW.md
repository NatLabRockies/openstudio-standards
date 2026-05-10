# OpenStudio-Standards Repository Review

**Review Date:** 2026-04-30  
**Reviewer:** Claude Code  
**Repository:** https://github.com/NREL/openstudio-standards

## Executive Summary

OpenStudio-Standards is a mature, well-maintained Ruby library with ~190K lines of code across 620 source files, 1,098 test files, and 140 contributors. The repository demonstrates good documentation practices, active development (1,866 commits in 2024-2026), and a comprehensive testing framework. However, there are opportunities for improvement in code organization, dependency management, technical debt reduction, and CI/CD modernization.

**Overall Assessment:** ⭐⭐⭐⭐ (4/5)

---

## 1. Code Architecture & Organization

### Strengths
✅ Well-defined inheritance hierarchy for standards implementation  
✅ Modular organization by functional domain (HVAC, geometry, schedules, etc.)  
✅ Clear separation between standards data (JSON) and code logic  
✅ Factory pattern for Standard class instantiation  
✅ Comprehensive YARD documentation coverage

### Issues Identified

#### 🔴 **CRITICAL: Code Duplication Between BTAP and Standards Modules**

**Problem:** The `/lib/openstudio-standards/btap/` directory contains duplicate implementations of methods already in `/lib/openstudio-standards/standards/necb/`. Rubocop explicitly excludes BTAP and NECB code from quality checks.

```ruby
# .rubocop.yml excludes:
- 'lib/openstudio-standards/btap/**/*'
- 'lib/openstudio-standards/standards/necb/**/*'
```

**Impact:**
- Code maintenance burden (fixing bugs in two places)
- Risk of divergent behavior between BTAP and standard implementations
- Larger library size and increased memory footprint
- Developer confusion about which module to use

**Recommendation:**
1. Create a migration plan to consolidate BTAP methods into the standard modules
2. Identify overlapping functionality using static analysis
3. Refactor NECB standards to inherit from BTAP where appropriate, or vice versa
4. Create deprecation warnings for duplicate BTAP methods
5. Remove rubocop exclusions once consolidation is complete

**Estimated Effort:** 3-6 months (high priority technical debt)

---

#### 🟡 **HIGH: Extremely Large Files**

**Problem:** Several files exceed 1,000 lines, with some approaching 8,000 lines:

- `do_not_edit_metaclasses.rb`: **40,372 lines** (auto-generated, but 1.6MB is excessive)
- `Prototype.hvac_systems.rb`: **7,528 lines**
- `Standards.Model.rb`: **6,349 lines** (108 methods in a single file)
- `hvac_systems.rb` (ECMS): **4,050 lines**
- `Standards.AirLoopHVAC.rb`: **3,939 lines**

**Impact:**
- Difficult to navigate and understand
- Slows down IDE performance
- Increases merge conflict likelihood
- Hard to write focused unit tests

**Recommendation:**
1. **Standards.Model.rb**: Split into separate concerns:
   - `Standards.Model.PRM.rb` (Performance Rating Method)
   - `Standards.Model.Simulation.rb` (simulation runs)
   - `Standards.Model.Validation.rb` (QAQC checks)
   - `Standards.Model.Baseline.rb` (baseline generation)

2. **Prototype.hvac_systems.rb**: Extract system types into individual files:
   - `Prototype.hvac_systems_vav.rb`
   - `Prototype.hvac_systems_pthp.rb`
   - `Prototype.hvac_systems_doas.rb`
   - etc.

3. **do_not_edit_metaclasses.rb**: Consider alternative approaches:
   - Generate smaller files per building type
   - Use lazy loading to reduce memory footprint
   - Investigate if metaprogramming can replace some generated code

**Estimated Effort:** 2-3 months

---

#### 🟡 **MEDIUM: Missing GitHub Actions / CI Configuration**

**Problem:** The repository uses Jenkins for CI (stored in external shared libraries), but has no local `.github/workflows/` configuration. This makes it:
- Difficult for contributors to understand the CI pipeline
- Impossible to run CI checks locally without Jenkins access
- Harder to contribute from forks (external contributors can't see CI results)

**Current State:**
```
.github/
├── pull_request_template.md  ✅
└── (no workflows/)  ❌
```

**Recommendation:**
1. Add GitHub Actions workflows for common tasks:
   - `.github/workflows/rubocop.yml` - Style checking on PRs
   - `.github/workflows/tests.yml` - Run subset of fast tests on PRs
   - `.github/workflows/documentation.yml` - Validate YARD docs build
   - `.github/workflows/bundler-audit.yml` - Security vulnerability scanning

2. Keep Jenkins for full test suite (can take hours)
3. Document CI architecture in `docs/ContinuousIntegration.md`

**Example GitHub Action:**
```yaml
name: RuboCop
on: [pull_request]
jobs:
  rubocop:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2.2
          bundler-cache: true
      - run: bundle exec rake rubocop
```

**Estimated Effort:** 1-2 weeks

---

## 2. Dependency Management

### Issues Identified

#### 🟡 **MEDIUM: Gemfile.lock Committed to Version Control**

**Problem:** Both `Gemfile.lock` and `Gemfile.lock.3.9.0` are tracked in git, but `.gitignore` excludes `Gemfile.lock`.

```bash
$ git status
M .devcontainer/setup.sh
$ ls Gemfile.lock*
Gemfile.lock  Gemfile.lock.3.9.0
```

**Impact:**
- Confusion about which lock file is authoritative
- Merge conflicts on every dependency update
- For a library gem, lock files should generally not be committed

**Recommendation:**
1. **If this is distributed as a gem** (which it is): Remove `Gemfile.lock` from version control
2. **If lock file is needed for reproducibility**: Keep only one, rename others
3. Update `.gitignore`:
   ```
   /Gemfile.lock*
   ```
4. Document dependency requirements in README for developers

**Rationale:** Per Bundler best practices, library gems should not commit lock files, only applications should.

**Estimated Effort:** 1 hour

---

#### 🟡 **MEDIUM: Outdated RuboCop Configuration**

**Problem:** RuboCop shows warnings about deprecated cop names:

```
Error: The `Metrics/LineLength` cop has been moved to `Layout/LineLength`.
(obsolete configuration found in .rubocop-http---s3-amazonaws-com-openstudio-resources-styles-rubocop-yml)
```

**Recommendation:**
1. Update inherited rubocop config at `http://s3.amazonaws.com/openstudio-resources/styles/rubocop.yml`
2. Or copy the config locally and maintain it in the repo
3. Run `bundle exec rubocop --auto-gen-config` to see all current violations
4. Address deprecated cops incrementally

**Estimated Effort:** 2-4 hours

---

#### 🟢 **LOW: HTTP Source for Gemfile**

**Problem:** `Gemfile` uses `http://rubygems.org` instead of `https://`

```ruby
source 'http://rubygems.org'  # Should be https
```

**Recommendation:** Change to `source 'https://rubygems.org'` for security

**Estimated Effort:** 5 minutes

---

## 3. Testing

### Strengths
✅ Excellent test coverage with 1,098 test files  
✅ Parallel test execution support  
✅ Well-organized test helpers  
✅ Separate test suites for different standards  
✅ CI integration for automated testing

### Issues Identified

#### 🟡 **MEDIUM: Test Organization Complexity**

**Problem:** Tests use multiple helper files with overlapping responsibilities:

```
test/helpers/
├── minitest_helper.rb (2,595 lines)
├── necb_helper.rb (23,865 lines)  ← Very large
├── create_doe_prototype_helper.rb (19,452 lines)
├── hvac_system_test_helper.rb (20,228 lines)
├── compare_models_helper.rb (20,170 lines)
├── ci_test_generator.rb (82,256 lines)  ← Extremely large
```

**Impact:**
- Hard to understand test dependencies
- Test helpers are almost as large as the code being tested
- Slow test startup time (loading large helpers)

**Recommendation:**
1. Break up large helper files by concern
2. Use Ruby's `autoload` for lazy loading of test utilities
3. Consider extracting common test fixtures to separate gem
4. Document test architecture in `docs/TestingStrategy.md`

**Estimated Effort:** 3-4 weeks

---

#### 🟢 **LOW: SimpleCov Disabled**

**Problem:** Code coverage tracking is commented out in `minitest_helper.rb`:

```ruby
=begin
require 'simplecov'
require 'codecov'
# ... coverage configuration
=end
```

**Recommendation:**
1. Re-enable SimpleCov for coverage tracking
2. Set coverage thresholds (aim for 80%+ for new code)
3. Publish coverage reports to Codecov or similar service
4. Add coverage badge to README.md

**Estimated Effort:** 2-4 hours

---

## 4. Documentation

### Strengths
✅ Comprehensive `/docs` directory with 97 markdown files  
✅ YARD documentation generation configured  
✅ Good PR template with checklist  
✅ Clear README with links to documentation  
✅ Excellent CLAUDE.md for AI-assisted development (newly added)

### Issues Identified

#### 🟡 **MEDIUM: Missing Contribution Guidelines**

**Problem:** No `CONTRIBUTING.md` file in the repository root. Contribution process is buried in `docs/DeveloperInformation.md`.

**Recommendation:**
1. Create `CONTRIBUTING.md` with:
   - Quick start for new contributors
   - How to run tests locally
   - Code style guidelines
   - PR submission process
   - Link to detailed docs
2. Add `CODE_OF_CONDUCT.md` (standard for open source projects)
3. Add `SECURITY.md` for vulnerability reporting

**Estimated Effort:** 4-6 hours

---

#### 🟢 **LOW: No Architecture Decision Records (ADRs)**

**Problem:** Major architectural decisions (e.g., why BTAP is separate from NECB standards) are not documented.

**Recommendation:**
1. Create `docs/adr/` directory
2. Document key decisions:
   - Why inheritance pattern was chosen for standards
   - Why JSON data is separated from code
   - Why BTAP exists separately from standard modules
   - Why metaclasses are auto-generated
3. Use lightweight ADR format (title, status, context, decision, consequences)

**Estimated Effort:** 1-2 weeks (as decisions are encountered)

---

## 5. Technical Debt

### Current Technical Debt Indicators

#### TODOs in Code
- **7 files** with TODO/FIXME comments in standards code
- Most relate to assumed efficiency values (SEER, EER, HSPF)

Example:
```ruby
# TODO: assumed to be the same as SEER for now
# TODO: assumed to be the same as EER for now
```

**Recommendation:** 
1. Track these TODOs as GitHub issues
2. Add links to issues in TODO comments: `# TODO: Fix #1234 - assumed SEER value`
3. Prioritize TODOs that affect accuracy of standards compliance

---

#### Code Smell: Large Methods
**Problem:** Many methods exceed 50 lines, some exceeding 200 lines (AbcSize: 200 allowed)

**Recommendation:**
1. Lower `Metrics/AbcSize` threshold gradually (200 → 150 → 100)
2. Refactor long methods into smaller, testable units
3. Use Extract Method refactoring pattern

---

#### Code Smell: Broad RuboCop Exclusions
**Problem:** Entire directories excluded from quality checks:
- `test/**/*` (understandable)
- `lib/openstudio-standards/btap/**/*` (concerning)
- `lib/openstudio-standards/standards/necb/**/*` (concerning)

**Recommendation:**
1. Create technical debt tickets for each excluded directory
2. Enable one cop at a time for excluded areas
3. Set up pre-commit hooks to prevent new violations

---

## 6. Security & Compliance

### Issues Identified

#### 🟡 **MEDIUM: No Automated Security Scanning**

**Problem:** No evidence of automated dependency vulnerability scanning.

**Recommendation:**
1. Enable GitHub Dependabot:
   - Create `.github/dependabot.yml`
   - Configure for bundler dependencies
2. Add `bundle audit` to CI pipeline
3. Schedule regular security audits (quarterly)

**Example Dependabot Config:**
```yaml
version: 2
updates:
  - package-ecosystem: "bundler"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
```

**Estimated Effort:** 2-3 hours

---

#### 🟢 **LOW: No LICENSE File in Repository Root**

**Problem:** License is in `LICENSE.md` (good) but not in standard `LICENSE` filename format that GitHub recognizes.

**Recommendation:**
1. Copy `LICENSE.md` to `LICENSE` (GitHub will auto-detect)
2. Keep `LICENSE.md` for compatibility
3. Verify license badge appears on GitHub repo page

**Estimated Effort:** 5 minutes

---

## 7. Developer Experience

### Issues Identified

#### 🟡 **MEDIUM: Complex Development Setup**

**Problem:** Setting up development environment requires:
1. Installing specific Ruby version
2. Installing specific OpenStudio version
3. Manually creating `openstudio.rb` file in system directories
4. Setting environment variables

**Recommendation:**
1. Enhance devcontainer configuration (already partially done)
2. Create Docker-based development environment
3. Add `bin/setup` script that automates setup steps
4. Document common setup issues in `docs/Troubleshooting.md`

**Estimated Effort:** 1-2 weeks

---

#### 🟢 **LOW: No Pre-commit Hooks**

**Problem:** No automated checks before commit to catch style violations early.

**Recommendation:**
1. Add `.git/hooks/pre-commit` script (or use `overcommit` gem)
2. Run RuboCop on staged files
3. Check for common issues:
   - Trailing whitespace
   - Merge conflict markers
   - Large files being committed
   - Sensitive data patterns

**Estimated Effort:** 4-6 hours

---

## 8. Data Management

### Issues Identified

#### 🟡 **MEDIUM: Manual Data Update Process**

**Problem:** Updating standards data requires:
1. Manual download from Google Spreadsheets
2. Saving to specific directory
3. Running rake task
4. Or making PRs to external database

**Recommendation:**
1. Automate spreadsheet sync using Google Sheets API
2. Create scheduled GitHub Action to check for data updates
3. Auto-generate PR when data changes detected
4. Document which data sources are canonical

**Estimated Effort:** 2-3 weeks

---

#### 🟢 **LOW: Large Binary Files in Repo**

**Problem:** Weather files (`.epw`, `.ddy`, `.stat`) and potentially large JSON files committed to git.

**Recommendation:**
1. Audit data file sizes: `find data -type f -size +1M`
2. Consider moving large files to Git LFS
3. Or host large files externally and download on-demand
4. Document data provenance and update procedures

**Estimated Effort:** 1-2 days

---

## 9. Recommendations Summary

### Priority 1 (Do First - High Impact, Achievable)
1. ✅ Add CLAUDE.md (DONE)
2. 🔧 Fix Gemfile.lock version control issue
3. 🔧 Change Gemfile source to HTTPS
4. 🔧 Add basic GitHub Actions workflows
5. 🔧 Create CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md
6. 🔧 Enable Dependabot for security scanning

**Estimated Total:** 2-3 weeks

---

### Priority 2 (Do Next - Technical Debt Reduction)
1. 🔧 Create migration plan for BTAP/NECB consolidation
2. 🔧 Split large files (Standards.Model.rb, Prototype.hvac_systems.rb)
3. 🔧 Update RuboCop configuration
4. 🔧 Re-enable SimpleCov code coverage
5. 🔧 Improve development setup automation

**Estimated Total:** 3-4 months

---

### Priority 3 (Long-term Improvements)
1. 🔧 Refactor test helpers
2. 🔧 Reduce method complexity (lower AbcSize threshold)
3. 🔧 Create Architecture Decision Records
4. 🔧 Automate data synchronization
5. 🔧 Remove RuboCop exclusions incrementally

**Estimated Total:** 6-12 months (ongoing)

---

## 10. Positive Highlights

The repository demonstrates many excellent practices:

✅ **Active Maintenance:** 1,866 commits in recent 16 months shows healthy development  
✅ **Strong Community:** 140 contributors indicate good collaboration  
✅ **Comprehensive Testing:** 1,098 test files provide safety net for refactoring  
✅ **Good Documentation:** 97 docs files, YARD coverage, clear architecture docs  
✅ **Professional PR Process:** Template with checklist ensures quality  
✅ **Modular Design:** Clear separation of concerns in directory structure  
✅ **Standards Compliance:** Implements multiple building energy codes accurately  
✅ **Open Source:** MIT-style license encourages adoption and contribution

---

## Conclusion

OpenStudio-Standards is a mature, well-architected library that serves an important role in building energy modeling. The codebase is generally healthy with good testing and documentation. The main areas for improvement are:

1. **Consolidating duplicate BTAP/NECB code** (highest priority technical debt)
2. **Breaking up extremely large files** for maintainability
3. **Modernizing CI/CD** with GitHub Actions
4. **Improving security posture** with automated scanning

These improvements will enhance maintainability, reduce onboarding friction for new contributors, and ensure long-term sustainability of the project.

**Recommended Next Steps:**
1. Share this review with the core team
2. Create GitHub issues for Priority 1 items
3. Schedule team discussion on BTAP/NECB consolidation strategy
4. Assign owners to each priority area

---

**Reviewer:** Claude Code (claude.ai/code)  
**Review Methodology:** Static analysis, structure review, best practices comparison  
**Scope:** Repository structure, code organization, documentation, testing, CI/CD, security
