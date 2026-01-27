#!/usr/bin/env bash
set -u

echo "Running Acceptance Tests..."

FAILED=0

fail() {
    echo "❌ $1"
    FAILED=1
}

pass() {
    echo "✅ $1"
}

# 1. Check entrypoint
if [ -x "./rb" ]; then
    pass "./rb exists and is executable"
else
    fail "./rb missing or not executable"
fi

# 2. Test preflight failure (mocking KFD missing)
echo "Testing preflight failure (missing /dev/kfd)..."
export TEST_PREFLIGHT_MOCK_KFD_MISSING=1
if ./rb prep full > /dev/null 2>&1; then
    fail "Preflight should have failed with missing /dev/kfd"
else
    pass "Preflight failed as expected with missing /dev/kfd"
fi
unset TEST_PREFLIGHT_MOCK_KFD_MISSING

# 3. Test dry-run of kickoff
echo "Testing kickoff.sh --dry-run..."
if ./scripts/kickoff.sh full --dry-run | grep -q "DRY-RUN"; then
    pass "kickoff.sh --dry-run works"
else
    fail "kickoff.sh --dry-run failed"
fi

if [ $FAILED -eq 0 ]; then
    echo "All acceptance tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
