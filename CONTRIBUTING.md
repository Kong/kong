# Contributing to Kong

## Got a question or problem?

Discuss it on the [Google Group](https://groups.google.com/forum/#!forum/konglayer) or chat with us on [Gitter](https://gitter.im/Mashape/kong).

## Found a bug?

We would like to hear about it. Please [submit an issue][new-issue] on GitHub and we will follow up. Even better, we would appreciate a [Pull Request][new-pr] (against the `next` branch) with a fix for it. If the fix is urgent, feel free to open the PR against the `master` branch.

## Want a feature?

Feel free to request a feature by [submitting an issue][new-issue] on GitHub and open the discussion.

If you'd like to implement a new feature, please consider opening an issue first to talk about it. It may be that somebody is already working on it, or that there are particular issues that you should be aware of before implementing the change. If you are about to open a Pull Request, please make sure to follow the [submissions guidelines][new-pr].

## Submission Guidelines

### Submitting an issue

Before you submit an issue, search the archive, maybe you will find that a similar one already exists.

If you are submitting an issue for a bug, please include the following:

- The platform you are running Kong on
- The version of Kong you are running
- Steps to reproduce the issue
- Eventually, logs from your `error.log` file. You can find this file at `<nginx_working_dir>/logs/error.log`

### Submitting a Pull Request

Before submitting your Pull Request please make sure to:

- Make the Pull Request against the `next` branch. If it's an urgent bugfix, then use the `master` branch.
- Include tests with your changes. If your changes introduce a new feature, please include tests with it. If it fixes a bug, please create a test to validate the fix.
- Rebase your commits. It may be that new commits have been introduced on the branch your are opening your Pull Request against. Rebasing will update your branch with the most resent code and make your changes easier to review.
- Consider squashing your commits. We prefer your initial changes to be squashed into a single commit. Later, if we ask you to make changes, add them as separate commits. This makes them easier to review. As a final step before merging we will either ask you to squash all commits yourself or we'll do it for you.
- Run the test suite with `make test-all`.

If all went well, we are eager to see your contribution, feel free to submit your Pull Request against the `next` branch.

[new-issue]: #submitting-an-issue
[new-pr]: #submitting-a-pull-request
