#!/bin/bash
set +x

# Check if gh CLI is installed
if ! command -v gh &> /dev/null
then
    echo "GitHub CLI (gh) is not installed. Please install it first."
    exit 1
fi

# Ensure the user is authenticated
gh auth status &>/dev/null
if [ $? -ne 0 ]; then
    echo "You are not authenticated with GitHub. Please authenticate using 'gh auth login'."
    exit 1
fi

# Get repository details and date range
REPO_OWNER="vcf"
read -p "Enter the start date (YYYY-MM-DD): " START_DATE
read -p "Enter the end date (YYYY-MM-DD): " END_DATE
read -p "Enter the file containing the list of usernames (one per line): " USER_FILE

# Check if the file exists
if [ ! -f "$USER_FILE" ]; then
    echo "The file '$USER_FILE' does not exist. Please provide a valid file."
    exit 1
fi

# Initialize summary file
SUMMARY_FILE="summary_$START_DATE_$END_DATE.csv"
SUMMARY_DIR="$END_DATE-Data"
mkdir "$SUMMARY_DIR"
echo "Userid,Username,RepoName,Total Commits,Total PRs,Total Reviews" > "$SUMMARY_FILE"

# Function to fetch commits
fetch_commits() {
    local username=$1
    local REPO_NAME=$2
    local output_file="$SUMMARY_DIR/$username-$REPO_NAME-commits.csv"
    echo >&2 "Fetching commits created by $username from $START_DATE to $END_DATE..."
    gh search commits "author-date:${START_DATE}..${END_DATE}" --repo "$REPO_OWNER/$REPO_NAME" --limit 1000 --author "$username"  --json id,committer,url --jq '.[] | [.id, .committer.login, .url] | @csv' > "$output_file"
    echo >&2 "$username commits saved to $output_file"
    COMMITS_COUNT=$(wc -l < "$output_file")
    echo $COMMITS_COUNT
}

# Function to fetch pull requests opened by the user
fetch_pull_requests() {
    local username=$1
    local REPO_NAME=$2
    local output_file="$SUMMARY_DIR/$username-$REPO_NAME-pull_requests.csv"
    echo  >&2 "Fetching pull requests created by $username from $START_DATE to $END_DATE..."
    gh pr list --repo "$REPO_OWNER/$REPO_NAME" --author "$username" --limit 1000 --state all --search "created:${START_DATE}..${END_DATE}" --json id,title,createdAt,author,url --jq '.[] | [.id, .title, .createdAt, .author.login, .author.name, .url] | @csv' > "$output_file"
    echo >&2  "$username pull requests saved to $output_file"
    PRS_COUNT=$(wc -l < "$output_file")
    echo $PRS_COUNT
}

# Function to fetch pull requests on which the user happens to be a reviewer
fetch_review_requests() {
    local username=$1
    local REPO_NAME=$2
    local output_file="$SUMMARY_DIR/$username-$REPO_NAME-review_requests.csv"
    echo  >&2 "Fetching pull requests reviewed by $username from $START_DATE to $END_DATE..."
    gh search prs --repo "$REPO_OWNER/$REPO_NAME" --limit 1000 "created:${START_DATE}..${END_DATE}"  --reviewed-by "$username" --json id,title,createdAt,author,url --jq '.[] | [.id, .title, .createdAt, .author.login, .author.name, .url] | @csv' | grep -v $username  > "$output_file"
    echo >&2  "$username reviewe requests saved to $output_file"
    PRS_COUNT=$(wc -l < "$output_file")
    echo $PRS_COUNT
}

# Process each username from the file
while IFS= read -r USERLINE; do
  # ToDo: add validation for the line we read from the file
  USERID=$(echo $USERLINE | cut -d ';' -f 1)
  USERNAME=$(echo $USERLINE | cut -d ';' -f 2)
  for REPO_NAME in netops-main netops-ui netops-operations ; do
    echo "Processing data for $USERID and repo $REPO_NAME..."

    # Fetch commits, PRs, and reviews for the user
    COMMITS_COUNT=$(fetch_commits "$USERID" "$REPO_NAME")
    echo "For repo $REPO_NAME got commits count $COMMITS_COUNT"

    PRS_COUNT=$(fetch_pull_requests "$USERID" "$REPO_NAME")
    echo "For repo $REPO_NAME got PRs count $PRS_COUNT"

    REVIEWS_COUNT=$(fetch_review_requests "$USERID" "$REPO_NAME")
    echo "For repo $REPO_NAME got review PR count $REVIEWS_COUNT"

    # Write summary to the summary.csv
    echo "$USERID,$USERNAME,$REPO_NAME,$COMMITS_COUNT,$PRS_COUNT,$REVIEWS_COUNT" >> "$SUMMARY_FILE"
  done
done < "$USER_FILE"

echo "Summary saved to $SUMMARY_FILE"
tar zcvf "$SUMMARY_DIR.tgz" "$SUMMARY_DIR/"
echo "Activity data for each user has been saved to individual CSV files."

