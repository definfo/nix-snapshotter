package testutil

import (
	"testing"

	"github.com/containerd/containerd/v2/pkg/testutil"
	"github.com/google/go-cmp/cmp"
)

func IsIdentical(t *testing.T, x interface{}, y interface{}) {
	diff := cmp.Diff(x, y)
	if diff != "" {
		t.Fatal(diff)
	}
}

var RequiresRoot = testutil.RequiresRoot
