#!/usr/bin/env bash

# below file has details about __DETAILED__ branch and __BACKUP__ branch
GIT_BRANCH_DETAILS_FILE_PATH="${HOME}/MyFiles/TaskFiles/GDrive/git-branch-details.txt"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)";
CURRENT_REPO_PATH="$(git rev-parse --show-toplevel)"

# detect long running branch
if git show-ref --quiet --verify refs/heads/develop ; then
  LONG_RUNNING_BRANCH=develop
elif git show-ref --quiet --verify refs/heads/master ; then
  LONG_RUNNING_BRANCH=master
elif git show-ref --quiet --verify refs/heads/main ; then
  LONG_RUNNING_BRANCH=main
else
  FZF_HEADER="Cannot find develop, master or main, so please choose long running branch (Press CTRL-C to cancel)"
  LONG_RUNNING_BRANCH="$(git branch --format='%(refname:short)'|fzf --header "$FZF_HEADER")"
fi

if [ -z "$LONG_RUNNING_BRANCH" ] ; then
  echo "INFO: exiting as long running branch is empty"
  exit 0;
fi

# detect if current branch is detail branch or feature branch
if echo "$CURRENT_BRANCH"| grep --silent '^.*__DETAILED__$' ; then
  echo "INFO: \"$CURRENT_BRANCH\" branch is a detail branch"
  DETAIL_BRANCH="${CURRENT_BRANCH}"
  FEATURE_BRANCH="$(grep "$DETAIL_BRANCH" "$GIT_BRANCH_DETAILS_FILE_PATH"|grep "${CURRENT_REPO_PATH}"|grep "__DETAILED__"|cut -d":" -f2)"
  BACKUP_BRANCH="$(grep "$FEATURE_BRANCH" "$GIT_BRANCH_DETAILS_FILE_PATH"|grep "${CURRENT_REPO_PATH}"|grep "__BACKUP__"|cut -d":" -f3)"
elif echo "$CURRENT_BRANCH"| grep --silent '^.*__BACKUP__$' ; then
  echo "INFO: \"$CURRENT_BRANCH\" branch is a backup branch"
  BACKUP_BRANCH="${CURRENT_BRANCH}"
  FEATURE_BRANCH="$(grep "$BACKUP_BRANCH" "$GIT_BRANCH_DETAILS_FILE_PATH"|grep "${CURRENT_REPO_PATH}"|grep "__BACKUP__"|cut -d":" -f2)"
  DETAIL_BRANCH="$(grep "$FEATURE_BRANCH" "$GIT_BRANCH_DETAILS_FILE_PATH"|grep "${CURRENT_REPO_PATH}"|grep "__DETAILED__"|cut -d":" -f3)"
elif [ "${CURRENT_BRANCH}" = "${LONG_RUNNING_BRANCH}" ] ; then
  echo "INFO: exiting as current branch is long running branch"
  exit 0;
else
  echo "\"$CURRENT_BRANCH\" branch is a feature branch"
  # truncate team name to avoid associating branch with JIRA ticket
  NEW_BRANCH_PREFIX="${CURRENT_BRANCH//DEV-/}"
  DETAIL_BRANCH="${NEW_BRANCH_PREFIX}__DETAILED__"
  BACKUP_BRANCH="${NEW_BRANCH_PREFIX}__BACKUP__"
  FEATURE_BRANCH="${CURRENT_BRANCH}"
  # append branch mapping to details file
  if ! grep --silent "$DETAIL_BRANCH" "$GIT_BRANCH_DETAILS_FILE_PATH" ; then
    # this is the first time detail branch and backup branch are being operated, so create them
    git branch "${DETAIL_BRANCH}" "${FEATURE_BRANCH}"
    git branch "${BACKUP_BRANCH}" "${FEATURE_BRANCH}"
    echo "${CURRENT_REPO_PATH}:${FEATURE_BRANCH}:${DETAIL_BRANCH}" >> "$GIT_BRANCH_DETAILS_FILE_PATH"
    echo "${CURRENT_REPO_PATH}:${FEATURE_BRANCH}:${BACKUP_BRANCH}" >> "$GIT_BRANCH_DETAILS_FILE_PATH"
  fi
fi

echo "INFO: Feature branch:          ${FEATURE_BRANCH}"
echo "INFO: Detailed commits branch: ${DETAIL_BRANCH}"
echo "INFO: Backup branch:           ${BACKUP_BRANCH}"

# git stash changes
if ! git status|grep --silent "working tree clean" ; then
  GIT_STASHED=true
  echo -e "INFO: stashing changes\n"
  git stash push
fi

if [ "$(git log --oneline "${FEATURE_BRANCH}"|head -1|cut -d" " -f1)" != "$(git log --oneline "${LONG_RUNNING_BRANCH}"|head -1|cut -d" " -f1)" ] ; then
  # reset feature branch to develop/master
  git switch "${LONG_RUNNING_BRANCH}"
  echo -e "INFO: resetting ${FEATURE_BRANCH} to ${LONG_RUNNING_BRANCH}\n"
  git branch -f "${FEATURE_BRANCH}" "${LONG_RUNNING_BRANCH}"

  # squash merge detail branch to feature branch
  # add commit messages in the new commit message
  GIT_COMMIT_MSGS="$(git log --oneline "$DETAIL_BRANCH" --not "$LONG_RUNNING_BRANCH"| cut -d" " -f2- )"
  FIRST_MSG="$(echo "${GIT_COMMIT_MSGS}"|tail -1)"
  GIT_COMMIT_MSGS="$(echo "${GIT_COMMIT_MSGS}"| head -n -1)"
  git switch "${FEATURE_BRANCH}"
  echo -e "INFO: creating squashed commit for feature branch\n"
  git merge --squash "${DETAIL_BRANCH}"
  git commit --m "${FIRST_MSG}" -m "${GIT_COMMIT_MSGS}"
  echo -e "INFO: detail branch task done"
  echo -e "------------------------------------\n"
fi

# backup branch, reset to detail branch, stash apply and commit
echo "INFO: resetting ${BACKUP_BRANCH} to ${DETAIL_BRANCH}"
git branch -f "${BACKUP_BRANCH}" "${DETAIL_BRANCH}"
# backup uncommitted changes
if [ "$GIT_STASHED" = true ] ; then
  git switch "${BACKUP_BRANCH}"
  echo "INFO: applying stash"
  git stash apply
  echo "INFO: adding all changes for backup commit"
  git add --all
  git commit --m "committing for backup - $(date)"
  echo -e "INFO: backup branch task done"
  echo -e "------------------------------------\n"
fi

# switch back to detail branch, this will be the working branch from now on
git switch "$DETAIL_BRANCH"

# restore stash
if [ "$GIT_STASHED" = "true" ] ; then
  echo "INFO: restoring stash"
  git stash pop
fi

# print 5 recent commits of detail and backup branch and ask for push confirmation
echo -e "\n\nrecent commits for branch ${DETAIL_BRANCH}"
echo -e "------------------------------------"
git log "${DETAIL_BRANCH}" --oneline|head -5
echo -e "\n\nrecent commits for branch ${BACKUP_BRANCH}"
echo -e "------------------------------------"
git log "${BACKUP_BRANCH}" --oneline|head -5

echo # print new line

# force push detail and backup branches, set upstream if required
if [ "$(git remote show|wc -l)" -ge 1 ] ; then
  
  # SHOULD_PUSH="$(echo -e "Yes\nNo"|fzf --header "should the above detail and backup branches be pushed to remote?")"
  # for now, always push without asking because even if something goes wrong, 
  # we will have remote feature branch which has the previous state before this script was run
  SHOULD_PUSH="Yes"

  if [ "$SHOULD_PUSH" = "Yes" ] ; then
    echo "INFO: pushing ${DETAIL_BRANCH}"
    git push --set-upstream "$(git remote show)" "${DETAIL_BRANCH}"
    echo "INFO: pushing ${BACKUP_BRANCH}"
    git push --set-upstream --force "$(git remote show)" "${BACKUP_BRANCH}"
  fi  
fi

true <<COMMENT
# commands to reset repo "https://github.com/overtomanu/simple-git-repo-with-feature-branches.git"
# to beginning state, so that this script can be tested again

git switch feature-branch1
git reset origin/feature-branch1
git reset --hard HEAD

git branch --delete feature-branch1__DETAILED__;
git push origin feature-branch1__DETAILED__ --delete;

git branch --delete feature-branch1__BACKUP__;
git push origin feature-branch1__BACKUP__ --delete;

trash "${HOME}/MyFiles/TaskFiles/GDrive/git-branch-details.txt"
touch "${HOME}/MyFiles/TaskFiles/GDrive/git-branch-details.txt"

# do changes for stash
git stash clear
echo -e "\n\nstash1 change1\n" >> test-file.txt

# run this git-sync.. script for testing
COMMENT