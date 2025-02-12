#!/bin/bash
set -x

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
read -p "Enter the repository owner: " REPO_OWNER
read -p "Enter the repository name: " REPO_NAME
read -p "Enter the start date (YYYY-MM-DD): " START_DATE
read -p "Enter the end date (YYYY-MM-DD): " END_DATE
read -p "Enter the file containing the list of usernames (one per line): " USER_FILE

# Check if the file exists
if [ ! -f "$USER_FILE" ]; then
    echo "The file '$USER_FILE' does not exist. Please provide a valid file."
    exit 1
fi

# Initialize summary file
SUMMARY_FILE="summary.csv"
echo "Username,Total Commits,Total PRs,Total Reviews" > "$SUMMARY_FILE"

# Function to fetch commits
fetch_commits() {
    local username=$1
    local output_file="$username-commits.csv"
    echo >&2 "Fetching commits created by $username from $START_DATE to $END_DATE..."
    gh search commits "author-date:${START_DATE}..${END_DATE}" --repo "$REPO_OWNER/$REPO_NAME" --limit 1000 --author "$username"  --json id,committer,url --jq '.[] | [.id, .committer.login, .url] | @csv' > "$output_file"
    echo >&2 "$username commits saved to $output_file"
    COMMITS_COUNT=$(wc -l < "$output_file")
    echo $COMMITS_COUNT
}

# Function to fetch pull requests opened by the user
fetch_pull_requests() {
    local username=$1
    local output_file="$username-pull_requests.csv"
    echo  >&2 "Fetching pull requests created by $username from $START_DATE to $END_DATE..."
    gh pr list --repo "$REPO_OWNER/$REPO_NAME" --author "$username" --limit 1000 --state all --search "created:${START_DATE}..${END_DATE}" --json id,title,createdAt,author,url --jq '.[] | [.id, .title, .createdAt, .author.login, .author.name, .url] | @csv' > "$output_file"
    echo >&2  "$username pull requests saved to $output_file"
    PRS_COUNT=$(wc -l < "$output_file")
    echo $PRS_COUNT
}

# Function to fetch pull requests on which the user happens to be a reviewer
fetch_review_requests() {
    local username=$1
    local output_file="$username-review_requests.csv"
    echo  >&2 "Fetching pull requests reviewed by $username from $START_DATE to $END_DATE..."
    gh search prs --repo "$REPO_OWNER/$REPO_NAME" --limit 1000 "created:${START_DATE}..${END_DATE}"  --reviewed-by "$username" --json id,title,createdAt,author,url --jq '.[] | [.id, .title, .createdAt, .author.login, .author.name, .url] | @csv' | grep -v $username  > "$output_file"
    echo >&2  "$username reviewe requests saved to $output_file"
    PRS_COUNT=$(wc -l < "$output_file")
    echo $PRS_COUNT
}

# Process each username from the file
while IFS= read -r USERNAME; do
    echo "Processing data for $USERNAME..."

    # Fetch commits, PRs, and reviews for the user
    COMMITS_COUNT=$(fetch_commits "$USERNAME")
    echo "Got commits count $COMMITS_COUNT"

    PRS_COUNT=$(fetch_pull_requests "$USERNAME")
    echo "Got PRs count $PRS_COUNT"

    REVIEWS_COUNT=$(fetch_review_requests "$USERNAME")
    echo "Got review PR count $REVIEWS_COUNT"

    # Write summary to the summary.csv
    echo "$USERNAME,$COMMITS_COUNT,$PRS_COUNT,$REVIEWS_COUNT" >> "$SUMMARY_FILE"
done < "$USER_FILE"

echo "Summary saved to $SUMMARY_FILE"
echo "Activity data for each user has been saved to individual CSV files."

