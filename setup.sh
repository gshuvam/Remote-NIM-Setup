#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="nvidia-nim"

echo "==> Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh

# Load uv into current shell
export PATH="$HOME/.local/bin:$PATH"

echo "==> Installing Python 3.14..."
uv python install 3.14

echo "==> Cloning repository..."
if [ -d "$PROJECT_DIR" ]; then
    echo "Directory '$PROJECT_DIR' already exists. Skipping clone."
else
    git clone https://github.com/gshuvam/free-claude-code.git "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"

echo "==> Creating .env file..."
if [ ! -f ".env" ]; then
    cp .env.example .env
fi

echo ""
echo "IMPORTANT:"
echo "Edit the .env file and replace:"
echo 'ANTHROPIC_AUTH_TOKEN="freecc"'
echo "with your real token."
echo ""

read -p "Press ENTER after updating the .env file..."

echo "==> Starting server..."
uv run uvicorn server:app --host 0.0.0.0 --port 8082
