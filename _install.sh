#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)    OS="macOS" ;;
        Linux*)     OS="Linux" ;;
        CYGWIN*|MINGW*|MSYS*)   OS="Windows" ;;
        *)          OS="Unknown" ;;
    esac
    print_status "Detected OS: $OS"
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Install Java (platform-specific)
install_java() {
    print_header "Installing Java"

    if command_exists java; then
        local java_version
        java_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 | cut -d'.' -f1)
        if [ "$java_version" -ge 11 ] 2>/dev/null; then
            print_status "Java $java_version is already installed."
            java -version 2>&1 | head -n3
            return 0
        else
            print_warning "Java $java_version found but Java 11+ is required."
        fi
    fi

    case "$OS" in
        macOS)
            if command_exists brew; then
                print_status "Installing OpenJDK 11 via Homebrew..."
                brew install openjdk@11
                print_status "Linking OpenJDK 11..."
                sudo ln -sfn "$(brew --prefix openjdk@11)/libexec/openjdk.jdk" \
                    /Library/Java/JavaVirtualMachines/openjdk-11.jdk 2>/dev/null || true
                print_status "Java installed successfully."
            else
                print_error "Homebrew is not installed. Please install it first:"
                print_error '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
                exit 1
            fi
            ;;
        Linux)
            if command_exists apt-get; then
                print_status "Installing OpenJDK 11 via apt..."
                sudo apt-get update
                sudo apt-get install -y openjdk-11-jdk
            elif command_exists yum; then
                print_status "Installing OpenJDK 11 via yum..."
                sudo yum install -y java-11-openjdk-devel
            elif command_exists pacman; then
                print_status "Installing OpenJDK 11 via pacman..."
                sudo pacman -S --noconfirm jdk11-openjdk
            else
                print_error "Could not detect package manager. Please install Java 11+ manually."
                exit 1
            fi
            ;;
        Windows)
            print_error "Automatic Java installation is not supported on Windows."
            print_error "Please download and install Java 11+ from:"
            print_error "  https://adoptium.net/temurin/releases/"
            exit 1
            ;;
        *)
            print_error "Unsupported OS. Please install Java 11+ manually."
            exit 1
            ;;
    esac
}

# Verify Git installation
verify_git() {
    print_header "Checking Git"

    if command_exists git; then
        print_status "Git is installed: $(git --version)"
    else
        print_error "Git is not installed. Please install Git first."
        case "$OS" in
            macOS)
                print_error "  brew install git"
                ;;
            Linux)
                print_error "  sudo apt-get install git (Debian/Ubuntu)"
                print_error "  sudo yum install git (RHEL/CentOS)"
                ;;
        esac
        exit 1
    fi
}

# Setup Gradle wrapper
setup_gradle() {
    print_header "Setting up Gradle"

    local gradle_wrapper="./gradlew"

    if [ ! -f "$gradle_wrapper" ]; then
        print_error "Gradle wrapper not found. Are you in the project root?"
        exit 1
    fi

    if [ ! -x "$gradle_wrapper" ]; then
        print_status "Making Gradle wrapper executable..."
        chmod +x "$gradle_wrapper"
    fi

    print_status "Verifying Gradle wrapper..."
    ./gradlew --version
    print_status "Gradle wrapper is ready."
}

# Create local environment file
setup_env() {
    print_header "Setting up local environment"

    if [ -f ".env" ]; then
        print_warning ".env file already exists. Skipping creation."
        print_warning "Delete .env and re-run to regenerate from template."
    else
        if [ -f ".env.example" ]; then
            print_status "Creating .env from .env.example..."
            cp .env.example .env
            print_status ".env file created. Edit it to customize your local settings."
        else
            print_warning "No .env.example found. Skipping .env creation."
        fi
    fi
}

# Verify Java environment variables
verify_java_env() {
    print_header "Verifying Java Environment"

    if [ -n "$JAVA_HOME" ]; then
        print_status "JAVA_HOME is set to: $JAVA_HOME"
    else
        print_warning "JAVA_HOME is not set."

        # Try to detect JAVA_HOME
        case "$OS" in
            macOS)
                local detected_java_home
                detected_java_home=$(/usr/libexec/java_home 2>/dev/null || true)
                if [ -n "$detected_java_home" ]; then
                    print_status "Detected JAVA_HOME: $detected_java_home"
                    print_warning "Consider adding to your shell profile:"
                    print_warning "  export JAVA_HOME=$detected_java_home"
                fi
                ;;
            Linux)
                if [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
                    print_status "Detected Java at /usr/lib/jvm/java-11-openjdk-amd64"
                    print_warning "Consider adding to your shell profile:"
                    print_warning '  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64'
                fi
                ;;
        esac
    fi

    # Verify java command
    if command_exists java; then
        local java_version
        java_version=$(java -version 2>&1 | head -n1)
        print_status "Java: $java_version"
    else
        print_error "Java command not found in PATH."
        exit 1
    fi

    # Verify javac command
    if command_exists javac; then
        local javac_version
        javac_version=$(javac -version 2>&1)
        print_status "Javac: $javac_version"
    else
        print_warning "javac not found. Make sure JDK (not just JRE) is installed."
    fi
}

# Run initial build
run_initial_build() {
    print_header "Running initial build"

    print_status "Compiling the client module..."
    ./gradlew :client:compileJava

    print_status "Initial compilation successful!"
    print_status ""
    print_status "To build the full shaded JAR, run:"
    print_status "  ./_main.sh --build"
    print_status ""
    print_status "To build and run the client, run:"
    print_status "  ./_main.sh --build"
}

# Main installation flow
main() {
    print_header "Microbot Development Environment Setup"
    echo ""

    detect_os
    echo ""

    verify_git
    echo ""

    install_java
    echo ""

    verify_java_env
    echo ""

    setup_gradle
    echo ""

    setup_env
    echo ""

    run_initial_build
    echo ""

    print_header "Setup Complete!"
    echo ""
    print_status "Your development environment is ready."
    print_status ""
    print_status "Quick start commands:"
    print_status "  ./_main.sh --build          Build and run the client"
    print_status "  ./_main.sh --build --clean   Clean build and run"
    print_status "  ./_main.sh --stop            Stop running instances"
    print_status "  ./_main.sh --help            Show all options"
    print_status ""
    print_status "For more information, see docs/development.md"
}

main "$@"
