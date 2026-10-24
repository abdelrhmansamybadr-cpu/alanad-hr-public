#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "===================================="
echo "  HR Portal - Local Development"
echo "===================================="
echo ""
echo "Starting API Server on http://localhost:3001"
echo "Starting HR Portal  on http://localhost:5173"
echo ""
echo "Press Ctrl+C to stop all services."
echo ""

cleanup() {
  echo ""
  echo "Stopping services..."
  kill $API_PID $FRONTEND_PID 2>/dev/null
  exit 0
}
trap cleanup SIGINT SIGTERM

cd "$SCRIPT_DIR/artifacts/api-server"
pnpm dev &
API_PID=$!

sleep 3

cd "$SCRIPT_DIR/artifacts/hr-portal"
pnpm dev &
FRONTEND_PID=$!

echo ""
echo "Services started:"
echo "  API Server:  http://localhost:3001/api/health"
echo "  HR Portal:   http://localhost:5173"
echo ""

wait $API_PID $FRONTEND_PID
