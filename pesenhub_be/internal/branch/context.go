package branch

import "context"

type contextKey struct{}

var scopeKey = contextKey{}

func WithScope(ctx context.Context, scope Scope) context.Context {
	return context.WithValue(ctx, scopeKey, scope)
}

func FromContext(ctx context.Context) (Scope, bool) {
	scope, ok := ctx.Value(scopeKey).(Scope)
	return scope, ok
}

func ScopeFromContext(ctx context.Context) Scope {
	scope, ok := ctx.Value(scopeKey).(Scope)
	if !ok {
		return Scope{}
	}
	return scope
}
