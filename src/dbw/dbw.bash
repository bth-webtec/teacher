#!/usr/bin/env bash
#
# A template for creating command line scripts taking options, commands
# and arguments.
#
# Exit values:
#  0 on success
#  1 on failure
#



# Name of the script
SCRIPT=$( basename "$0" )

# Current version
VERSION="1.0.0"



##
# Message to display for version.
#
version ()
{
    local txt=(
"$SCRIPT version $VERSION"
    )

    printf "%s\\n" "${txt[@]}"
}



##
# Message to display for usage and help.
#
usage ()
{
    local txt=(
"Work with a course by connecting to Canvas and GitHub."
"Usage: $SCRIPT [options] <command> [arguments]"
""
"Command:"
"  invite <email | acronym>         Invite a new member to the org using email or GH user acronym."
"  members                          Get all members on the organisation of GitHub."
"  members <team>                   Get all members in a specific team."
"  membership <acronym>             Check if acronym is member of the organisation."
"  pages <name>                     Get details of GitHub pages for a repo."
"  repo <name>                      Get details of a repo."
"  user                             Get details of your own user (troubleshoot the token)."
""
"Options:"
"  --help, -h     Print help."
"  --version, -h  Print version."
    )

    printf "%s\\n" "${txt[@]}"
}



##
# Message to display when bad usage.
#
badUsage ()
{
    local message="$1"
    local txt=(
"For an overview of the command, execute:"
"$SCRIPT --help"
    )

    [[ -n $message ]] && printf "%s\\n" "$message"

    printf "%s\\n" "${txt[@]}" >&2
    exit 1
}



##
# Error while processing
#
# @param string $* error message to display.
#
fail ()
{
    local color
    local normal

    color=$(tput setaf 1)
    normal=$(tput sgr0)

    printf "%s $*\\n" "${color}[FAILED]${normal}"
    exit 2
}



##
# Invite new member to the organisation by email.
#
# @arg string email   The email to invite, should be connected to a github account.
#
app_invite ()
{
    local email="$1"
    local id=
    local url="$GITHUB_API_URL/orgs/$GITHUB_ORGANISATION/invitations"
    local auth="Authorization: Bearer $GITHUB_ACCESS_TOKEN"
    local accept="Accept: application/vnd.github+json"
    local res=

    (( $# != 1)) \
        && fail "This command requires one argument <email>."

    if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "Looks like an email."
        res=$( curl --silent -X POST "$url" -H "$auth" -H "$accept" \
            -d "{\"email\": \"$email\", \"role\": \"direct_member\"}" )
    else
        echo "Does not look like an email, using it as a GitHub account name to lookup an id."
        id=$( curl -s "$GITHUB_API_URL/users/$email" | jq '.id' )
        echo "id=$id"
        res=$( curl --silent -X POST "$url" -H "$auth" -H "$accept" \
            -d "{\"invitee_id\": $id, \"role\": \"direct_member\"}" )
    fi

    echo "$res" | jq
}



##
# Get all members of the GitHub organisation or of a specific team in the org.
#
# @arg string team   OPTIONAL The name of the team.
#
app_members ()
{
    local url_members="$GITHUB_API_URL/orgs/$GITHUB_ORGANISATION/members?per_page=500&page=1"
    local auth="Authorization: Bearer $GITHUB_ACCESS_TOKEN"
    local accept="Accept: application/vnd.github+json"
    local team="$1"
    local url_team="$GITHUB_API_URL/orgs/$GITHUB_ORGANISATION/teams/$team/members?per_page=500&page=1"
    local res=
    
    if [[ -z $team ]]; then
        res=$( curl --silent "$url_members" -H "$auth" -H "$accept" )
    else
        res=$( curl --silent "$url_team" -H "$auth" -H "$accept" )
    fi

    if (( VERBOSE )); then
        echo "$res" | jq
    else
        echo "$res" | jq -r '.[] | "\(.login) \(.html_url)"'
    fi
}



##
# Check membership of the organisation for a member.
#
# @arg string acronym   The acronym to check membership.
#
app_membership ()
{
    local acronym="$1"
    local url="$GITHUB_API_URL/orgs/$GITHUB_ORGANISATION/memberships/$acronym"
    local auth="Authorization: Bearer $GITHUB_ACCESS_TOKEN"
    local accept="Accept: application/vnd.github+json"
    local res=

    (( $# != 1)) \
        && fail "This command requires one argument <acronym>."

    (( VERBOSE )) \
        && echo "$url"

    res=$( curl --silent "$url" -H "$auth" -H "$accept" )

    if (( VERBOSE )); then
        echo "$res" | jq
    else
        echo "$res" | jq '{url, state, role}'
    fi
}



##
# Get details of the pages setup.
#
# @arg string repo   The repo name.
#
app_pages ()
{
    local repo="$1"
    local url="$GITHUB_API_URL/repos/$GITHUB_ORGANISATION/$repo/pages"
    local auth="Authorization: Bearer $GITHUB_ACCESS_TOKEN"
    local accept="Accept: application/vnd.github+json"
    local res=

    (( $# != 1)) \
        && fail "This command requires one argument <repo name>."

    res=$( curl --silent "$url" -H "$auth" -H "$accept" )

    if (( VERBOSE )); then
        echo "$res" | jq
    else
        echo "$res" | jq '{ "html_url": .html_url }'
    fi
}



##
# Get details of a repo.
#
# @arg string repo   The repo name.
#
app_repo ()
{
    local repo="$1"
    local url="$GITHUB_API_URL/repos/$GITHUB_ORGANISATION/$repo"
    local auth="Authorization: Bearer $GITHUB_ACCESS_TOKEN"
    local accept="Accept: application/vnd.github+json"
    local res=

    (( $# != 1)) \
        && fail "This command requires one argument <repo name>."

    res=$( curl --silent "$url" -H "$auth" -H "$accept" )

    if (( VERBOSE )); then
        echo "$res" | jq
    else
        echo "$res" | jq '{ "repo": .name, "html_url": .html_url }'
    fi
}



##
# Get details on my own user.
#
app_user ()
{
    local url="$GITHUB_API_URL/user"
    local auth="Authorization: Bearer $GITHUB_ACCESS_TOKEN"

    (( VERBOSE )) \
        && echo "$url"

    curl --silent -i "$url" -H "$auth"
}



##
# Update the date for expires at for the specified student with the id.
#
# @arg string id        The student id to update.
# @arg string expire    The date to expire-at.
#
app_expire ()
{
    local id="$1"
    local expire="$2"
    local status

    (( $# != 2)) \
        && fail "This command requires two arguments <id> <expire-at>."

    status=$( curl --silent --output /dev/null --write-out "%{http_code}" \
        -X PATCH "$BASE_URL/$id"                    \
        -H "X-API-Private-Token: $ACCESS_TOKEN"     \
        -H "Content-Type: application/json"         \
        --data '{"expiresAt": "'"$expire"'"}'       \
    )
    echo "$status"
}



##
# Always have a main
# 
main ()
{
    local command
    local args

    while (( $# ))
    do
        case "$1" in

            --help | -h)
                usage
                exit 0
            ;;

            --verbose | -v)
                VERBOSE=1
                shift
            ;;

            --version)
                version
                exit 0
            ;;

            invite           \
            | members        \
            | membership     \
            | pages          \
            | repo           \
            | user           \
            )
                if [[ ! $command ]]; then
                    command=$1
                else
                    args+=("$1")
                fi
                shift
            ;;

            -*)
                badUsage "Unknown option '$1'."
            ;;

            *)
                if [[ ! $command ]]; then
                    badUsage "Unknown command '$1'."
                else
                    args+=("$1")
                    shift
                fi
            ;;

        esac
    done

    # Execute the command 
    if type -t app_"$command" | grep -q function; then
        app_"$command" "${args[@]}"
    else
        badUsage "Missing option or command."
    fi
}

# shellcheck source=/dev/null
[[ -f .env ]] && source .env

main "$@"
