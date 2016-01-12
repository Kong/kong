# Contributing to Kong

### Got a question or problem?

Discuss it on the [Google Group](https://groups.google.com/forum/#!forum/konglayer) or chat with us on [Gitter](https://gitter.im/Mashape/kong) or freenode in [#kong](http://webchat.freenode.net/?channels=kong).

### Browsing the code?

We work on two branches: `master` for stable, released code and `next`, a development branch. It might be important to distinguish them when you are reading the commit history searching for a feature or a bugfix, or when you are unsure of where to base your work from when contributing.

### Found a bug?

We would like to hear about it. Please [submit an issue][new-issue] on GitHub and we will follow up. Even better, we would appreciate a [Pull Request][new-pr] with a fix for it!

- If the bug was found in a release, it is best to base your work on `master` and submit your PR against it.
- If the bug was found on `next` (the development branch), base your work on `next` and submit your PR against it.

Please follow the [Pull Request Guidelines][new-pr].

### Want a feature?

Feel free to request a feature by [submitting an issue][new-issue] on GitHub and open the discussion.

If you'd like to implement a new feature, please consider opening an issue first to talk about it. It may be that somebody is already working on it, or that there are particular issues that you should be aware of before implementing the change. If you are about to open a Pull Request, please make sure to follow the [submissions guidelines][new-pr].

## Submission Guidelines

### Submitting an issue

Before you submit an issue, search the archive, maybe you will find that a similar one already exists.

If you are submitting an issue for a bug, please include the following:

- An overview of the issue
- Your use case (why is this a bug for you?)
- The version of Kong you are running
- The platform you are running Kong on
- Steps to reproduce the issue
- Eventually, logs from your `error.log` file. You can find this file at `<nginx_working_dir>/logs/error.log`
- Ideally, a suggested fix

The more informations you give us, the more able to help we will be!

### Submitting a Pull Request

- First of all, make sure to base your work on the `next` branch (the development branch):

  ```
  # a bugfix branch for next would be prefixed by fix/
  # a bugfix branch for master would be prefixed by hotfix/
  $ git checkout -b feature/my-feature next
  ```

- Please create commits containing **related changes**. For example, two different bugfixes should produce two separate commits. A feature should be made of commits splitted by **logical chunks** (no half-done changes). Use your best judgement as to how many commits your changes require.

- Write insightful and descriptive commit messages. It lets us and future contributors quickly understand your changes without having to read your changes. Please provide a summary in the first line (50-72 characters) and eventually, go to greater lengths in your message's body. We also like commit message with a **type** and **scope**. We generally follow the [Angular commit message format](https://github.com/angular/angular.js/blob/master/CONTRIBUTING.md#commit-message-format).

- Please **include the appropriate test cases** for your patch.

- Make sure all tests pass before submitting your changes. See the [Makefile operations](/README.md#makefile-operations).

- Make sure the linter does not throw any error: `make lint`.

- Rebase your commits. It may be that new commits have been introduced on `next`. Rebasing will update your branch with the most recent code and make your changes easier to review:

  ```
  $ git fetch
  $ git rebase origin/next
  ```

- Push your changes:

  ```
  $ git push origin -u feature/my-feature
  ```

- Open a pull request against the `next` branch.

- If we suggest changes:
  - Please make the required updates (after discussion if any)
  - Only create new commits if it makes sense. Generally, you will want to amend your latest commit or rebase your branch after the new changes:

    ```
    $ git rebase -i next
    # choose which commits to edit and perform the updates
    ```

  - Re-run the test suite
  - Force push to your branch:

    ```
    $ git push origin feature/my-feature -f
    ```

We are eager to see your contribution!

[new-issue]: #submitting-an-issue
[new-pr]: #submitting-a-pull-request
