def shrink(items, fails):
    items = list(items)
    chunk = len(items) // 2
    while chunk >= 1:
        i = 0
        changed = False
        while i < len(items):
            trial = items[:i] + items[i + chunk :]
            if trial and fails(trial):
                items = trial
                changed = True
            else:
                i += chunk
        if not changed:
            chunk //= 2
    return items
