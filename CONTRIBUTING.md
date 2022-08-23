# How to Contribute

We want your help to make the Samvera community great. There are a few guidelines
that we need contributors to follow so that we can have a chance of
keeping on top of things.

## Code of Conduct

The Samvera Community is dedicated to providing a welcoming and positive
experience for all its members, whether they are at a formal gathering, in
a social setting, or taking part in activities online. Please see our
[Code of Conduct](CODE_OF_CONDUCT.md) for more information.

## Language

The language we use matters.  Today, tomorrow, and for years to come
people will read the code we write.  They will judge us for our
design, logic, and the words we use to describe the system.

Our words should be accessible.  Favor descriptive words that give
meaning while avoiding reinforcing systemic inequities.  For example,
in the Samvera community, we should favor using allowed\_list instead
of whitelist, denied\_list instead of blacklist, or source/copy
instead of master/slave.

We're going to get it wrong, but this is a call to keep working to
make it right.  View our code and the words we choose as a chance to
have a conversation. A chance to grow an understanding of the systems
we develop as well as the systems in which we live.

See [“Blacklists” and “whitelists”: a salutary warning concerning the
prevalence of racist language in discussions of predatory
publishing](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6148600/) for
further details.

## Contribution Tasks

* Reporting Issues
* Making Changes
* Documenting Code
* Committing Changes
* Submitting Changes
* Reviewing and Merging Changes

### Reporting Issues

* Make sure you have a [GitHub account](https://github.com/signup/free)
* Submit a [Github issue](https://github.com/samvera/{{library}}/issues/) by:
  * Clearly describing the issue
    * Provide a descriptive summary
    * Explain the expected behavior
    * Explain the actual behavior
    * Provide steps to reproduce the actual behavior
    * Include which version of Bulkrax is being used if a bug is being reported
  * Attach screen shots and/or video recordings where possible
* Add the issue to the "Bulkrax | Main Board" project using the "Projects" option on the right side of the page

### Making Changes

* Fork the repository on GitHub
* Create a topic branch from where you want to base your work.
  * This is usually the `main` branch.
  * To quickly create a topic branch based on `main`; `git branch i<issue_number>-<description> main`
    * e.g.: `i123-add-more-documentation`
  * Then checkout the new branch with `git checkout i123-add-more-documentation`.
  * Please avoid working directly on the `main` branch.
  * Please do not create a branch called `master`. (See note below.)
  * You may find the [hub suite of commands](https://github.com/defunkt/hub) helpful
* Make sure you have added sufficient tests and documentation for your changes.
  * Test functionality with RSpec; Test features / UI with Capybara.
* Run _all_ the tests to assure nothing else was accidentally broken.

NOTE: This repository follows the [Samvera Community Code of Conduct](https://samvera.atlassian.net/wiki/spaces/samvera/pages/405212316/Code+of+Conduct)
and [language recommendations](#language).
Please ***do not*** create a branch called `master` for this repository or as part of
your pull request; the branch will either need to be removed or renamed before it can
be considered for inclusion in the code base and history of this repository.

### Documenting Code

* All new public methods, modules, and classes should include inline documentation in [YARD](http://yardoc.org/).
  * Documentation should seek to answer the question "why does this code exist?"
* Document private / protected methods as desired.
* If you are working in a file with no prior documentation, do try to document as you gain understanding of the code.
  * If you don't know exactly what a bit of code does, it is extra likely that it needs to be documented. Take a stab at it and ask for feedback in your pull request. You can use the 'blame' button on GitHub to identify the original developer of the code and @mention them in your comment.
  * This work greatly increases the usability of the code base and supports the on-ramping of new committers.
  * We will all be understanding of one another's time constraints in this area.
* [Getting started with YARD](http://www.rubydoc.info/gems/yard/file/docs/GettingStarted.md)

### Committing changes

* Make commits of logical units.
* Check for unnecessary whitespace with `git diff --check` before committing.
* Make sure your commit messages are [well formed](http://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html).

```
    Present tense short summary (50 characters or less)

    More detailed description, if necessary. It should be wrapped to 72
    characters. Try to be as descriptive as you can, even if you think that
    the commit content is obvious, it may not be obvious to others. You
    should add such description also if it's already present in bug tracker,
    it should not be necessary to visit a webpage to check the history.

    Description can have multiple paragraphs and you can use code examples
    inside, just indent it with 4 spaces:

        class PostsController
          def index
            respond_to do |wants|
              wants.html { render 'index' }
            end
          end
        end

    You can also add bullet points:

    - you can use dashes or asterisks

    - also, try to indent next line of a point for readability, if it's too
      long to fit in 72 characters
```

* Make sure you have added the necessary tests for your changes.
* Run _all_ the tests to assure nothing else was accidentally broken.
* When you are ready to, submit a pull request

### Submitting Changes

* Read the article ["Using Pull Requests"](https://help.github.com/articles/using-pull-requests) on GitHub.
* Make sure your branch is up to date with its parent branch (i.e. main)
  * `git checkout main`
  * `git pull`
  * `git checkout <your-branch>`
  * `git merge main`
    * fix merge conflicts if any
  * It is a good idea to run your tests again.
* If you've made more than one commit take a moment to consider whether squashing commits together would help improve their logical grouping.
  * [Detailed Walkthrough of One Pull Request per Commit](http://ndlib.github.io/practices/one-commit-per-pull-request/)
  * Squashing your branch's changes into one commit is "good form" and helps the person merging your request to see everything that is going on.
* Push your changes to a topic branch in your fork of the repository.
* Submit a pull request from your fork to the project.
* Link your pull request to the related issue using the "Development" option on the right side of the issue or pull request. If there is no corresponding issue, please create one. (Unless the change is something like adding a spec, updating the readme, etc. and not a feature/bug fix that needs tracking.)

### Reviewing and Merging Changes

We adopted [Github's Pull Request Review](https://help.github.com/articles/about-pull-request-reviews/) for our repositories.
Common checks that may occur in our repositories:

1. [CircleCI](https://circleci.com/gh/samvera) - where our automated tests are running
2. RuboCop/Bixby - where we check for style violations
3. Approval Required - Github enforces at least one person approve a pull request. Also, all reviewers that have chimed in must approve.
4. CodeClimate - is our code remaining healthy (at least according to static code analysis)
5. Required Labels - the label required by [samvera-lab's cla-bot](https://github.com/samvera-labs/cla-bot) and an appropriate [semver](https://semver.org/) label (see [release.yml](https://github.com/samvera-labs/bulkrax/blob/main/.github/release.yml))

If one or more of the required checks failed (or are incomplete), the code should not be merged (and the UI will not allow it). If all of the checks have passed, then anyone on the project (including the pull request submitter) may merge the code.

*Example: Carolyn submits a pull request, Justin reviews the pull request and approves. However, Justin is still waiting on other checks (CI tests are usually the culprit), so he does not merge the pull request. Eventually, all of the checks pass. At this point, Carolyn or anyone else may merge the pull request.*

#### Things to Consider When Reviewing

First, the person contributing the code is putting themselves out there. Be mindful of what you say in a review.

* Ask clarifying questions
* State your understanding and expectations
* Provide example code or alternate solutions, and explain why

This is your chance for a mentoring moment of another developer. Take time to give an honest and thorough review of what has changed. Things to consider:

  * Does the commit message explain what is going on?
  * Does the code changes have tests? _Not all changes need new tests, some changes are refactorings_
  * Do new or changed methods, modules, and classes have documentation?
  * Does the commit contain more than it should? Are two separate concerns being addressed in one commit?
  * Does the description of the new/changed specs match your understanding of what the spec is doing?
  * Did the Continuous Integration tests complete successfully?

If you are uncertain, bring other contributors into the conversation by assigning them as a reviewer.

## Running the spec suite
### Set up the test database
``` bash
bundle exec rake db:create
bundle exec rake db:migrate
bundle exec rake bin/rails db:migrate RAILS_ENV=test
```

### Run the specs
```  bash
# let's say you have cloned bulkrax into a folder titled "vendor" in your project;
# update the project gemfile to point at that local version of bulkrax. e.g.:
gem 'bulkrax', path: 'vendor/bulkrax'

# go into that folder (if you use Docker, this is done outside of containers)
cd vendor/bulkrax

# run your specs using one of the following
bin/rake (all specs)
bin/rspec (all specs)
bin/rspec <path-to-file> (single file)
  e.g. bin/rspec spec/models/bulkrax/csv_entry_spec.rb
```

### Troubleshooting the spec suite
If you're unable to run migrations in the test environment, you may need to go into the test database itself to make the necessary changes before attempting to migrate again.

- Example error: "SQLite3::SQLException: table "bulkrax_pending_relationships" already exists"
  ``` bash
  rails db test
    sqlite> .tables # confirm the bulkrax_pending_relationships table exists
    sqlite> drop table bulkrax_pending_relationships; # delete the bulkrax_pending_relationships table
    sqlite> .tables # confirm the bulkrax_pending_relationships table doesn't exist
    sqlite> .quit # exit the sqlite db
  rails db:migrate RAILS_ENV=test # should succeed! (barring no other migrations were failing)
  ```

- Example error: SQLite3::SQLException: duplicate column name: parents: ALTER TABLE "bulkrax_importer_runs" ADD "parents" text
  ``` bash
  rails db test
    sqlite> ALTER TABLE "bulkrax_importer_runs" DROP "parents"; # delete the "parents" column
    sqlite> .quit # exit the sqlite db
  rails db:migrate RAILS_ENV=test # should succeed! (barring no other migrations were failing)
  ```

## Running rubocop
Learn about the `-a` flag [here](https://docs.rubocop.org/rubocop/usage/basic_usage.html#auto-correcting-offenses)
```
bundle exec rubocop -a <path-to-file> (single file)
```

# Additional Resources

* [General GitHub documentation](http://help.github.com/)
* [GitHub pull request documentation](https://help.github.com/articles/about-pull-requests/)
* [Pro Git](http://git-scm.com/book) is both a free and excellent book about Git.
* [A Git Config for Contributing](http://ndlib.github.io/practices/my-typical-per-project-git-config/)

# Thank You!

Thank you for your interest in contributing to Bulkrax.  We appreciate you for taking the time to contribute.
