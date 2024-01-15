#  git-feature-branch-backup-and-dual-maintenance

Test repo for testing shell script : [git-sync-detail-and-backup-branch.sh](./git-sync-detail-and-backup-branch.sh)

This script creates and pushes backup and detail branches for a given feature branch
After this script is run,

- feature branch will have single squashed commit
- detail branch will have all the commits which were done manually
- backup branch will have all the commits plus a commit backing up working tree changes

Uses:

- Doing quick backup of a feature branch.
- You need to have single commit per feature in main branch, but you need to maintain detailed commits for reference in another branch
