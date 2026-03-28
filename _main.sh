#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --build                   Build the project before starting (default: false)"
    echo "  --stop                    Stop running RuneLite instances and exit"
    echo "  --profile <name>          Use a specific profile (default: default)"
    echo "  --credentials <path>      Path to Jagex credentials file (default: ~/.runelite/credentials.properties)"
    echo "  --local-plugins <path>    Path to local plugins directory"
    echo "  --debug                   Enable remote debugging on port 5005"
    echo "  --clean                   Clean build artifacts before building"
    echo "  --skip-run                Build only, do not run the client"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                        Run the client (no build)"
    echo "  $0 --build                Build and run the client"
    echo "  $0 --build --clean        Clean, build and run the client"
    echo "  $0 --build --skip-run     Build only without running"
    echo "  $0 --stop                 Stop all running instances"
    echo "  $0 --profile myprofile    Run with a custom profile"
    echo "  $0 --credentials /path/to/creds.properties  Use custom credentials file"
    echo "  $0 --local-plugins /path/to/plugins  Use local plugins directory"
    echo "  $0 --debug                Run with remote debugging enabled"
}

# Default values
BUILD=false
STOP=false
PROFILE="default"
CREDENTIALS_PATH="${HOME}/.runelite/credentials.properties"
LOCAL_PLUGINS_PATH=""
DEBUG=false
CLEAN=false
SKIP_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --build)
            BUILD=true
            shift
            ;;
        --stop)
            STOP=true
            shift
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --credentials)
            CREDENTIALS_PATH="$2"
            shift 2
            ;;
        --local-plugins)
            LOCAL_PLUGINS_PATH="$2"
            shift 2
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --skip-run)
            SKIP_RUN=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Load local environment if .env file exists
if [ -f ".env" ]; then
    print_status "Loading local environment from .env"
    set -a
    # shellcheck source=/dev/null
    source .env
    set +a
fi

# Load Jagex Launcher credentials if available
RUNELITE_CREDENTIALS="$CREDENTIALS_PATH"
if [ -f "$RUNELITE_CREDENTIALS" ]; then
    print_status "Loading Jagex Launcher credentials from $RUNELITE_CREDENTIALS"
    # Export credentials as environment variables
    export JX_CHARACTER_ID=$(grep '^JX_CHARACTER_ID=' "$RUNELITE_CREDENTIALS" | cut -d'=' -f2)
    export JX_SESSION_ID=$(grep '^JX_SESSION_ID=' "$RUNELITE_CREDENTIALS" | cut -d'=' -f2)
    export JX_DISPLAY_NAME=$(grep '^JX_DISPLAY_NAME=' "$RUNELITE_CREDENTIALS" | cut -d'=' -f2)
    export JX_REFRESH_TOKEN=$(grep '^JX_REFRESH_TOKEN=' "$RUNELITE_CREDENTIALS" | cut -d'=' -f2)
    export JX_ACCESS_TOKEN=$(grep '^JX_ACCESS_TOKEN=' "$RUNELITE_CREDENTIALS" | cut -d'=' -f2)
    
    if [ -n "$JX_CHARACTER_ID" ] && [ -n "$JX_SESSION_ID" ]; then
        print_status "Jagex account loaded: $JX_DISPLAY_NAME (Character ID: $JX_CHARACTER_ID)"
    fi
else
    if [ "$CREDENTIALS_PATH" != "${HOME}/.runelite/credentials.properties" ]; then
        print_warning "Credentials file not found at: $RUNELITE_CREDENTIALS"
    fi
fi

# Project configuration
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRADLE_WRAPPER="${PROJECT_DIR}/gradlew"
CLIENT_MODULE=":client"
SHADED_JAR_DIR="${PROJECT_DIR}/runelite-client/build/libs"
MICROBOT_VERSION=$(grep 'microbot.version=' "${PROJECT_DIR}/gradle.properties" | cut -d'=' -f2)
RUNELITE_VERSION=$(grep 'project.build.version=' "${PROJECT_DIR}/gradle.properties" | cut -d'=' -f2)

# Derived paths
SHADED_JAR="${SHADED_JAR_DIR}/runelite-client-${RUNELITE_VERSION}-shaded.jar"
MICROBOT_JAR="${SHADED_JAR_DIR}/microbot-${MICROBOT_VERSION}.jar"

# Function to find running instances
find_running_instances() {
    pgrep -f "runelite-client.*shaded\|microbot-.*\.jar" 2>/dev/null || true
}

# Function to stop running instances
stop_instances() {
    local pids
    pids=$(find_running_instances)
    if [ -n "$pids" ]; then
        print_status "Stopping running RuneLite/Microbot instances..."
        echo "$pids" | while read -r pid; do
            if [ -n "$pid" ]; then
                print_status "Stopping process $pid"
                kill "$pid" 2>/dev/null || true
            fi
        done
        sleep 2
        # Force kill if still running
        pids=$(find_running_instances)
        if [ -n "$pids" ]; then
            print_warning "Force killing remaining instances..."
            echo "$pids" | while read -r pid; do
                if [ -n "$pid" ]; then
                    kill -9 "$pid" 2>/dev/null || true
                fi
            done
        fi
        print_status "All instances stopped."
    else
        print_status "No running instances found."
    fi
}

# Handle stop command
if [ "$STOP" = true ]; then
    stop_instances
    exit 0
fi

# Verify Java installation
verify_java() {
    if ! command -v java &> /dev/null; then
        print_error "Java is not installed or not in PATH."
        print_error "Please install Java 11+ and ensure it is in your PATH."
        print_error "Run './_install.sh' to set up your development environment."
        exit 1
    fi

    local java_version
    java_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2)
    # Handle both old-style (1.8.x) and new-style (11.x, 17.x) version formats
    local major_version
    major_version=$(echo "$java_version" | cut -d'.' -f1)
    if [ "$major_version" = "1" ]; then
        major_version=$(echo "$java_version" | cut -d'.' -f2)
    fi
    if [ "$major_version" -lt 11 ] 2>/dev/null; then
        print_error "Java 11+ is required. Found version: $java_version"
        exit 1
    fi

    print_status "Java version: $(java -version 2>&1 | head -n1)"
}

# Verify Gradle wrapper
verify_gradle() {
    if [ ! -f "$GRADLE_WRAPPER" ]; then
        print_error "Gradle wrapper not found at: $GRADLE_WRAPPER"
        print_error "Are you running this script from the project root?"
        exit 1
    fi

    if [ ! -x "$GRADLE_WRAPPER" ]; then
        print_status "Making Gradle wrapper executable..."
        chmod +x "$GRADLE_WRAPPER"
    fi
}

# Build the project
build_project() {
    print_status "Building Microbot (version: $MICROBOT_VERSION)..."

    if [ "$CLEAN" = true ]; then
        print_status "Cleaning build artifacts..."
        "$GRADLE_WRAPPER" cleanAll
    fi

    print_status "Running Gradle build..."
    "$GRADLE_WRAPPER" ${CLIENT_MODULE}:shadowJar ${CLIENT_MODULE}:microbotReleaseJar

    if [ -f "$MICROBOT_JAR" ]; then
        print_status "Build successful: $MICROBOT_JAR"
    elif [ -f "$SHADED_JAR" ]; then
        print_status "Build successful: $SHADED_JAR"
    else
        print_error "Build completed but JAR not found in: $SHADED_JAR_DIR"
        ls -la "$SHADED_JAR_DIR" 2>/dev/null || print_error "Build output directory does not exist."
        exit 1
    fi
}

# Run the client
run_client() {
    local jar_to_run=""

    # Prefer microbot jar, fall back to shaded jar
    if [ -f "$MICROBOT_JAR" ]; then
        jar_to_run="$MICROBOT_JAR"
    elif [ -f "$SHADED_JAR" ]; then
        jar_to_run="$SHADED_JAR"
    else
        print_error "No runnable JAR found. Please build first with: $0 --build"
        exit 1
    fi

    # Build JVM arguments
    local jvm_args=()
    
    # Add macOS-specific exports for Java 11+ module system
    if [[ "$OSTYPE" == "darwin"* ]]; then
        jvm_args+=("--add-exports" "java.desktop/com.apple.eawt=ALL-UNNAMED")
    fi
    
    if [ "$DEBUG" = true ]; then
        print_status "Debug mode enabled on port 5005"
        jvm_args+=("-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:5005")
    fi
    
    # Add Jagex Launcher credentials as system properties if available
    if [ -n "$JX_SESSION_ID" ]; then
        jvm_args+=("-Djagex.launcher=true")
        jvm_args+=("-Djagexlauncher.session=$JX_SESSION_ID")
        jvm_args+=("-Djagexlauncher.characterid=$JX_CHARACTER_ID")
        [ -n "$JX_DISPLAY_NAME" ] && jvm_args+=("-Djagexlauncher.displayname=$JX_DISPLAY_NAME")
        [ -n "$JX_REFRESH_TOKEN" ] && jvm_args+=("-Djagexlauncher.refreshtoken=$JX_REFRESH_TOKEN")
        [ -n "$JX_ACCESS_TOKEN" ] && jvm_args+=("-Djagexlauncher.accesstoken=$JX_ACCESS_TOKEN")
        print_status "Using Jagex Launcher authentication"
    fi
    
    jvm_args+=("-jar" "$jar_to_run")

    # Add profile argument if not default
    local app_args=()
    if [ "$PROFILE" != "default" ]; then
        print_status "Using profile: $PROFILE"
        app_args+=("--profile" "$PROFILE")
    fi
    
    # Add local plugins path as environment variable if specified
    if [ -n "$LOCAL_PLUGINS_PATH" ]; then
        if [ -d "$LOCAL_PLUGINS_PATH" ]; then
            print_status "Using local plugins from: $LOCAL_PLUGINS_PATH"
            export MICROBOT_LOCAL_PLUGINS_PATH="$LOCAL_PLUGINS_PATH"
        else
            print_warning "Local plugins directory not found: $LOCAL_PLUGINS_PATH"
        fi
    fi

    print_status "Starting Microbot client..."
    print_status "JAR: $jar_to_run"

    # Run in background
    java "${jvm_args[@]}" "${app_args[@]}" &
    local client_pid=$!

    print_status "Client started with PID: $client_pid"
    print_status "Use '$0 --stop' to stop the client."
}

# Main execution
cd "$PROJECT_DIR"

verify_java
verify_gradle

if [ "$BUILD" = true ]; then
    build_project
fi

if [ "$SKIP_RUN" = false ]; then
    run_client
fi

print_status "Done."
