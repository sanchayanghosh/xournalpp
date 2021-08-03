#!/bin/bash

# Get the path of the script
SCRIPT_PATH=$(dirname $(realpath -s $0))

# Parse current version string
function current_major_version() {
    echo $(sed -n 's/^set (CPACK_PACKAGE_VERSION_MAJOR "\([0-9]\+\)")/\1/p' ${SCRIPT_PATH}/../CMakeLists.txt)
}

function current_minor_version() {
    echo $(sed -n 's/^set (CPACK_PACKAGE_VERSION_MINOR "\([0-9]\+\)")/\1/p' ${SCRIPT_PATH}/../CMakeLists.txt)
}

function current_patch_version() {
    echo $(sed -n 's/^set (CPACK_PACKAGE_VERSION_PATCH "\([0-9]\+\)")/\1/p' ${SCRIPT_PATH}/../CMakeLists.txt)
}

function current_suffix_version() {
    echo $(sed -n 's/^set (VERSION_SUFFIX "\(-[^\"]*\)")/\1/p' ${SCRIPT_PATH}/../CMakeLists.txt)
}

function current_version() {
    echo $(current_major_version)$(current_minor_version)$(current_patch_version)$(current_suffix_version)
}

function parse_major_version() {
    echo $(echo $1 | sed -n 's/^\([0-9]\+\)\..*$/\1/p')
}

function parse_minor_version() {
    echo $(echo $1 | sed -n 's/^[0-9]\+\.\([0-9]\+\)\..*$/\1/p')
}

function parse_patch_version() {
    echo $(echo $1 | sed -n 's/^[0-9]\+\.[0-9]\+\.\([0-9]\+\).*$/\1/p')
}

function parse_suffix_version() {
    echo $(echo $1 | sed -n 's/^[0-9]\+\.[0-9]\+\.[0-9]\+-\(.*\)$/\1/p')
}

# Compares two versions $1 and $2
# If $2 is greater it returns 1
function compare_versions() {
    if ( printf "%s\n%s" "$1" "$2" | LC_ALL=C sort -CVu ); then
        return 1
    fi
    return 0
}

# Validates the provided version string
# $1 the version as a string
# Returns 1 if the version is valid
function validate_version() {
    if ! [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+([+~][A-Za-z0-9+~]*)*?$ ]]; then
        return 1
    else
        if [[ $1 =~ ~dev$ ]]; then
            return 0
        fi
        return 1
    fi
}

# Print information about the correct format of a version string
function print_version_help() {
    echo "Please supply the version of the release in the format (0.0.0<suffix>)"
    echo "The suffix is optional, starts with a '+' or '~' and may only contain alphanumeric characters and '+' or '~'."
    echo "Within the suffix '+' is evaluated as a higher release and '~' as a lower release than the basic version number."
}

# Abort execution
# $1 The exit code
# $2 The message to print before abort
function abort() {
    echo "ABORT: $2"
    exit $1
}

# Check if branch already exists
# $1 The name of the branch
# If it exists returns 0
function branch_exists() {
    if git rev-parse --quiet --verify $1 > /dev/null; then
        return 0
    fi
    return 1
}

# Check if release already exists
# $1 The version string of the release
# If it exists returns 0
function release_exists() {
    if git tag | grep -Fxq "v$1"; then
        return 0
    fi
    return 1
}

# Check if git is in detached head mode
# If yes returns 1
function is_detached() {
    if git status --branch --porcelain | grep -Fxq "## HEAD (no branch)"; then
        return 0
    fi
    return 1
}

# Bumps the version in all relevant places
# Should the prior version be the same version but with an added ~dev this version is replaced
# $1 The version string
function bump_version() {
    local prior_version=$(current_version)

    # If the prior version was the same but ended with ~dev replace it instead
    if [[ $prior_version -eq "$1~dev" ]]; then
        local replace=1
    else
        local replace=0
    fi

    # Update version in the CMakeLists.txt
    sed -i "s/set (CPACK_PACKAGE_VERSION_MAJOR \"[0-9]\+\")/set (CPACK_PACKAGE_VERSION_MAJOR \"$(parse_major_version $1)\")/g" $SCRIPT_PATH/../CMakeLists.txt
    sed -i "s/set (CPACK_PACKAGE_VERSION_MINOR \"[0-9]\+\")/set (CPACK_PACKAGE_VERSION_MINOR \"$(parse_minor_version $1)\")/g" $SCRIPT_PATH/../CMakeLists.txt
    sed -i "s/set (CPACK_PACKAGE_VERSION_PATCH \"[0-9]\+\")/set (CPACK_PACKAGE_VERSION_PATCH \"$(parse_patch_version $1)\")/g" $SCRIPT_PATH/../CMakeLists.txt
    sed -i "s/set (VERSION_SUFFIX \"[^\"]*\")/set (VERSION_SUFFIX \"$(parse_suffix_version $1)\")/g" ${SCRIPT_PATH}/../CMakeLists.txt

    # From now on current_*_version functions return the new version

    # Update Changelog
    if [ $replace -eq 0 ]; then
        sed -i "N;s/# Changelog\n\n/# Changelog\n\n## $(current_version) (Unreleased)\n\n/g" $SCRIPT_PATH/../CHANGELOG.md
    else
        sed -i "s/## ${prior_version} (Unreleased)\n/## $(current_version)\n\n/g" $SCRIPT_PATH/../CHANGELOG.md
    fi

    # Update Debian Changelog
    local GIT_USER=$(git config --get user.name)
    if [ $? -ne 0 ]; then
        abort 2 "Could not read current git user - Please set with 'git config --set user.name <name>'"
    fi
    local GIT_MAIL=$(git config --get user.email)
    if [ $? -ne 0 ]; then
        abort 2 "Could not read current git user email - Please set with 'git config --set user.email <email>'"
    fi
    local DATE=$(date --rfc-2822)

    if [ $replace -eq 0 ]; then
        sed -i "1i xournalpp ($(current_version)-1) UNRELEASED; urgency=medium\n\n  * \n\n -- ${GIT_USER} <${GIT_MAIL}>  ${DATE}\n" $SCRIPT_PATH/../debian/changelog
    else
        sed -i "s/xournalpp (${prior_version}-1) UNRELEASED; urgency=medium/xournalpp ($(current_version)-1) unstable; urgency=medium/g" $SCRIPT_PATH/../debian/changelog
        sed -i "/xournalpp ($(current_version)-1)/,/xournalpp/s/ --.*/ -- ${GIT_USER} <${GIT_MAIL}>  ${DATE}/g" $SCRIPT_PATH/../debian/changelog
    fi

    # Update Appdata
    local DATE=$(date +%Y-%m-%d)

    if [ $replace -eq 0 ]; then
        sed -i "1,/^    <release .*$/ {/^    <release .*$/i\
        \ \ \ \ <release date=\"$DATE\" version=\"$(current_version)\" />
        }" $SCRIPT_PATH/../desktop/com.github.xournalpp.xournalpp.appdata.xml
    else
        sed -i "s/\ \ \ \ <release date=\".*\" version=\"${prior_version}\" />/\ \ \ \ <release date=\".*\" version=\"$(current_version)\" />/g" $SCRIPT_PATH/../desktop/com.github.xournalpp.xournalpp.appdata.xml
    fi

    echo "Bumped version from $prior_Version to $(current_version)"
}

# Prepares a new version
# A new version differs in the major or minor version part from the last.
# Assumes it is on the main development branch
# $1 The version string for the new version
function prepare_new_version() {

    # Check for a valid modification of the version strings
    if (compare_versions "$(current_major_version).$(current_minor_version).0" "$(parse_major_version $1).$(parse_minor_version $1).0"); then
        abort 7 "The provided version is not higher than the current one."
    fi

    # Create release branch
    local branch_name="release-$(parse_major_version $1).$(parse_minor_version $1)"
    git branch --quiet $branch_name
    if [ $? -ne 0 ]; then
        abort 8 "Could not create new release branch"
    fi

    # Bump version of main development branch
    bump_version "$(parse_major_version $1).$(($(parse_minor_version $1) + 1)).0~dev"
    if [ $? -ne 0 ]; then
        abort 9 "Could not bump version of main development branch"
    fi

    # Commit version bump
    git commit -a -m "Automated version bump to $(parse_major_version $1).$(($(parse_minor_version $1)+1)).0~dev"
    if [ $? -ne 0 ]; then
        abort 10 "Could not commit version bump on main development branch"
    fi

    # Checkout release branch
    git checkout --quiet $branch_name
    if [ $? -ne 0 ]; then
        abort 11 "Could not check out new release branch"
    fi

    # Bump version of main development branch
    bump_version $1
    if [ $? -ne 0 ]; then
        abort 9 "Could not bump version of new release branch"
    fi

    # Commit version bump
    git commit --quiet -a -m "Automated version bump to $1"
    if [ $? -ne 0 ]; then
        abort 10 "Could not commit version bump on new release branch"
    fi

    echo "SUCCESS: New release $1 was successfully prepared"
    echo "You are now on the release branch ($branch_name)."
    echo "Please check the last commit on the current branch and master for consistency"
    echo "and push your changes with:"
    echo ""
    echo "    git push origin master $branch_name"
    echo ""
    echo "Should the commit not meet your expectations, you may amend the changes."
    echo "BUT do not modify the version numbers!"
}

# Prepares a patch
# A patch only differs on the patch level from the previous version
# Assumes it is on the release branch
# $1 The version string of the new patch
function prepare_patch() {
    # Check for a valid modification of the version strings
    if [[ $(parse_major_version $1) -ne $(current_major_version) ]]; then
        abort 6 "The major version may not increase on a release branch. Instead create the version from the main development branch."
    fi
    if [[ $(parse_minor_version $1) -ne $(current_minor_version) ]]; then
        abort 6 "The minor version may not increase on a release branch. Instead create the version from the main development branch."
    fi
    if [[ $(compare_versions $(current_version) $1) -ne 1 ]]; then
        abort 7 "The provided version is not higher than the current one."
    fi

    # Bump version
    bump_version $1
    if [ $? -ne 0 ]; then
        abort 9 "Could not bump version of new release branch"
    fi

    # Commit version bump
    git commit -a -m "Automated version bump to $1"
    if [ $? -ne 0 ]; then
        abort 10 "Could not commit version bump on new release branch"
    fi

    echo "SUCCESS: New release $1 was successfully prepared"
    echo "Please check the last commit on the current branch for consistency and push your changes with:"
    echo ""
    echo "    git push origin"
    echo ""
    echo "Should the commit not meet your expectations, you may amend the changes."
    echo "BUT do not modify the version numbers!"
}

# Prepares a hotfix
# A hotfix may only differ in the version suffix from its base release
# Assumes it is on the commit of the release
# $1 The version string for the hotfix
function prepare_hotfix() {
    # Check for a valid modification of the version strings
    if [[ $(parse_major_version $1) -ne $(current_major_version) ]]; then
        abort 6 "The major version may not differ from the base release for a hotfix."
    fi
    if [[ $(parse_minor_version $1) -ne $(current_minor_version) ]]; then
        abort 6 "The minor version may not differ from the base release for a hotfix."
    fi
    if [[ $(parse_patch_version $1) -ne $(current_patch_version) ]]; then
        abort 6 "The patch version may not differ from the base release for a hotfix."
    fi

    if [[ $(compare_versions $(current_version) $1) -ne 1 ]]; then
        abort 7 "The provided version is not higher than the release it is based on."
    fi

    local branch_name="hotfix-$1"

    # Check if branch already exists
    if [[ $(branch_exists $branch_name) -eq 0 ]]; then
        abort 8 "The branch for this release already exists. Use this branch directly instead."
    fi

    # Check if hotfix was already released
    if [[ $(release_exists $1) -eq 0 ]]; then
        abort 8 "The release already exists."
    fi

    # Check out new release-branch
    git checkout --quiet -b $branch_name
    if [ $? -ne 0 ]; then
        abort 9 "Could not check out new release branch"
    fi

    # Bump version
    bump_version $1
    if [ $? -ne 0 ]; then
        abort 10 "Could not set version of release"
    fi

    # Commit version bump
    git commit -a -m "Automated version bump to $1"
    if [ $? -ne 0 ]; then
        abort 10 "Could not commit version bump on new release branch"
    fi

    echo "SUCCESS: New release $1 was successfully prepared"
    echo "You are now on the release branch ($branch_name)."
    echo "Please check the last commit on the current branch for consistency and push your changes with:"
    echo ""
    echo "    git push origin"
    echo ""
}

function publish_release() {
    if ! [[ $(read -e -p 'Are you sure you want to publish this release? [y/N] '; echo $REPLY) =~ ^[Yy]+$ ]]; then
        exit 0
    fi

    # Check for a clean git working space - otherwise this script will commit whatever is there
    if ! git diff --quiet --cached --exit-code > /dev/null; then
        abort 3 "Your working tree is not clean. Please commit or stash all staged changes before running this script."
    fi

    if ! [[ $branch =~ ^(release-[0-9]+\.[0-9]+|hotfix-[0-9]+\.[0-9]+\.[0-9]+([+~][A-Za-z0-9+~]*))?$ ]]; then
        abort 4 "You are not on a release or hotfix branch. Are you on the right branch?"
    fi

    # Merge the release branch to releases
    #git checkout --quiet releases
    #if [ $? -ne 0 ]; then
    #    abort 5 "Ooops the branch for releases does not exist..."
    #fi

    #Strip ~dev from the version
    bump_version $(echo $(current_version)|sed 's/~dev$//g')

    # Commit version bump
    git commit -a -m "Release $(current_version)"
    if [ $? -ne 0 ]; then
        abort 5 "Could not commit version bump for release"
    fi

    # We can not use a releases branch. Otherwise providing a patch to a version that is older than the last is impossible
    #echo "Merging $branch into releases..."
    #git merge --no-ff -m "Release $(current_version)" $branch
    #if [ $? -ne 0 ]; then
    #    abort 6 "Merge of release failed. Did you rebase commits that were already released priorly!?"
    #fi

    # Tag the release
    echo "Tagging the release"
    git tag -a "v$(current_version)" -m "Release $(current_version)"
    if [ $? -ne 0 ]; then
        abort 6 "Could not tag release"
    fi

    # Bump the version to the next patch and add ~dev again if we are on a release-branch
    if ! [[ $branch =~ ^release-[0-9]+\.[0-9]+$ ]]; then
        bump_version "$(current_major_version).$(current_minor_version).$(($(current_patch_version)+1)).$(current_suffix_version)~dev"
    fi

    # Commit version bump
    git commit -a -m "Automated version bump to $(current_version)"
    if [ $? -ne 0 ]; then
        abort 7 "Could not commit version bump after release"
    fi

    echo "SUCCESS: Release was published locally!"
    echo "To publish the release globally push your changes with:"
    echo ""
    echo "    git push --follow-tags origin release-$(current_major_version).$(current_minor_version)"
    echo ""

    if ! [[ $(read -e -p 'Do you want to merge back to the main development branch now? [Y/n] '; echo $REPLY) =~ ^[Nn]+$ ]]; then
        #echo "Once the merge is successfully finished, and you do not plan on future patches you may delete the release branch with:"
        #echo ""
        #echo "    git branch -d $branch"
        #echo ""

        # Merge the release branch back to master
        git checkout --quiet master
        git merge --no-ff -m "Release $(current_version)" $branch
    fi
}

####################
# Main functionality
####################

# Check for a version number passed by argument
if [ "$#" -lt 1 ]; then
    echo "Missing command"
    command="help"
else
    command=$1
fi

if [[ $command != @(help|prepare|publish) ]]; then
    echo "ABORT: unknown command"
    command="help"
fi

if [[ $command == "help" ]]; then
    echo "Usage: $0 <command> <arguments>"
    echo ""
    echo "Commands:"
    echo "  prepare <version>  Prepares a release in the form of a new branch with correct version strings."
    echo "                     This command may only be run on a clean HEAD from:"
    echo "                       - The main development branch (master)"
    echo "                           The supplied version must differ from the current version in the major"
    echo "                           or minor version level. The suffix string may differ in any way."
    echo "                       - A release branch (release-*)"
    echo "                           The supplied version must differ from the current version in the patch"
    echo "                           version level and must be higher than the current version. The suffix"
    echo "                           string may differ in any way."
    echo "                       - A commit of a published release (has a Tag starting with 'v'"
    echo "                           The supplied version must differ from the current version in the suffix"
    echo "                           and must be higher than the current version."
    echo "                     The supplied version suffix may not end with '~dev'. This ending is a"
    echo "                     protected suffix and is applied by the script automatically."
    echo ""
    echo "    publish          Publishes a priorly prepared release. You must be on a branch that that was"
    echo "                     created during the prepare phase of this script. The version of the release"
    echo "                     is derived from the prepare phase. Make sure to update the changelogs prior"
    echo "                     to starting this phase. Changelogs are contained in:"
    echo "                       - CHANGELOG"
    echo "                       - debian/changelog"
    echo ""
    echo "    help             Prints this help message"
    echo ""
fi

# Check on which branch we are
branch=$(git branch --show-current)
if [ $? -ne 0 ]; then
    abort 2 "Could not determine the current branch"
fi

if [[ $command == "prepare" ]]; then
    version=$2
    # Check for a clean git working space - otherwise this script will commit whatever is there
    if ! git diff --quiet --cached --exit-code > /dev/null; then
        abort 3 "Your working tree is not clean. Please commit or stash all staged changes before running this script."
    fi

    if validate_version $1; then
        print_version_help
        abort 4 "No valid version string provided"
    fi

    if [[ $branch == "master" ]]; then
        # Disallow detached HEAD
        if is_detached; then
            abort 5 "You can not prepare a release in detached HEAD mode"
        fi
        prepare_new_version $version
    elif [[ $branch =~ ^release-.*$ ]]; then
        # Disallow detached HEAD
        if is_detached; then
            abort 5 "You can not prepare a release in detached HEAD mode"
        fi
        prepare_patch $version
    elif [[ $(git tag --contains | grep -Exc '^v[0-9]+.[0-9]+.[0-9]+([+~][0-9A-Za-z+~]*)*$') -ne 0 ]]; then
        prepare_hotfix $version
    else
        abort 4 "You may only call this script from the main development branch, an existing release branch or a tagged release."
    fi
elif [[ $command == "publish" ]]; then
    publish_release
fi
