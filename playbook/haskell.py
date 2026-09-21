from functools import reduce as _reduce, partial, cache as memo, cmp_to_key
from itertools import accumulate as _acc, islice as _islice, pairwise as _pairwise
from itertools import chain, count, cycle, repeat
from operator import add, sub, mul, not_, eq
from math import gcd, lcm, hypot, isqrt, prod as product
from collections import Counter, defaultdict, deque
from heapq import heappush, heappop, merge as _hmerge
import re as _re
# 1. functions
identity = lambda x: x
const = lambda x: lambda *_: x
flip = lambda f: lambda a,b: f(b,a)
curry = lambda f: lambda x: lambda y: f(x,y)
uncurry = lambda f: lambda p: f(*p)
def compose(*fs):
    def g(x):
        for f in reversed(fs):
            x = f(x)
        return x
    return g
o = compose
def pipe(x,*fs):
    for f in fs:
        x = f(x)
    return x
on = lambda f,g: lambda x,y: f(g(x),g(y))
# 2. pairs
fst = lambda p: p[0]
snd = lambda p: p[1]
swap = o(tuple,reversed)
# 3. sentinels
class _Sentinel:
    __slots__ = ("_n",)
    def __init__(self,n): self._n = n
    def __repr__(self): return self._n
    def __bool__(self): return False
NOTHING = _Sentinel("NOTHING")
FAIL = _Sentinel("FAIL")
_MISS = _Sentinel("_MISS")
# 4. arithmetic & logic
div = lambda a,b: a // b
mod = lambda a,b: a % b
halve = lambda n: n // 2
even = lambda n: n % 2 == 0
odd = lambda n: n % 2 == 1
otherwise = True
quot = lambda a,b: -(-a // b) if (a < 0) != (b < 0) else a // b
rem = lambda a,b: a - b * quot(a,b)
quotRem = lambda a,b: (quot(a,b), rem(a,b))
signum = lambda x: (x > 0) - (x < 0)
succ = lambda x: chr(ord(x) + 1) if isinstance(x,str) else x + 1
pred = lambda x: chr(ord(x) - 1) if isinstance(x,str) else x - 1
# 5. folds, scans, unfolds
foldl = lambda f,xs,base=_MISS: _reduce(f,xs) if base is _MISS else _reduce(f,xs,base)
foldr = lambda f,xs,base: _reduce(flip(f),reversed(list(xs)),base)
foldl1 = foldl
foldr1 = lambda f,xs: _reduce(flip(f),reversed(list(xs)))
scanl = lambda f,xs,base=_MISS: list(_acc(xs,f) if base is _MISS else _acc(xs,f,initial=base))
scanl1 = scanl
scanr = lambda f,xs,base: scanl(flip(f),reversed(list(xs)),base)[::-1]
scanr1 = lambda f,xs: scanl(flip(f),reversed(list(xs)))[::-1]
def unfoldr(f,seed):
    out = []
    while (r := f(seed)) is not NOTHING:
        out.append(r[0]); seed = r[1]
    return out
def until(cond,f,x):
    while not cond(x):
        x = f(x)
    return x
replicateM = lambda n,xs: foldl(lambda acc,_: [s + [x] for s in acc for x in xs],range(n),[[]])
subsequences = lambda xs: foldl(lambda acc,x: acc + [s + [x] for s in acc],list(xs),[[]])
# 6. streams
def iterate(f,x):
    while True:
        yield x
        x = f(x)
take = lambda n,xs: list(_islice(iter(xs),n))
# 7. list basics
head = lambda xs: xs[0]
tail = lambda xs: xs[1:]
init = lambda xs: xs[:-1]
last = lambda xs: xs[-1]
drop = lambda n,xs: list(xs)[max(n,0):]
splitAt = lambda n,xs: (xs[:n], xs[n:]) if n >= 0 else (xs[:0], xs)
replicate = lambda n,x: [x] * n
elem = lambda x,xs: x in xs
notElem = lambda x,xs: x not in xs
null = lambda xs: len(xs) == 0
nub = o(list,dict.fromkeys)
enum = lambda xs,start=0: list(enumerate(xs,start))
pairwise = lambda xs: list(_pairwise(xs))
zip_ = lambda a,b: list(zip(a,b))
zip3 = lambda a,b,c: list(zip(a,b,c))
unzip = lambda ps: tuple(map(list,zip(*ps))) if ps else ([], [])
isPrefixOf = lambda p,xs: list(xs[:len(p)]) == list(p)
isSuffixOf = lambda p,xs: list(xs[len(xs) - len(p):]) == list(p)
lookup = lambda k,pairs: next((v for kk, v in pairs if kk == k),NOTHING)
stripPrefix = lambda p,xs: xs[len(p):] if isPrefixOf(p,xs) else NOTHING
# 8. higher-order lists
map_ = lambda f,xs: [f(x) for x in xs]
filter_ = lambda cond,xs: [x for x in xs if cond(x)]
concat = lambda xss: [x for xs in xss for x in xs]
concatMap = lambda f,xs: [y for x in xs for y in f(x)]
cross = lambda a,b: [(x, y) for x in a for y in b]
starmap = lambda f,pairs: [f(*p) for p in pairs]
zipWith = lambda f,a,b: [f(x,y) for x, y in zip(a,b)]
zipWith3 = lambda f,a,b,c: [f(x,y,z) for x, y, z in zip(a,b,c)]
find = lambda cond,xs: next((x for x in xs if cond(x)),NOTHING)
def partition(cond,xs):
    yes, no = [], []
    for x in xs:
        (yes if cond(x) else no).append(x)
    return (yes, no)
# 9. slicing & spans
def span(cond,xs):
    xs = list(xs)
    i = next((i for i, x in enumerate(xs) if not cond(x)),len(xs))
    return (xs[:i], xs[i:])
break_ = lambda cond,xs: span(o(not_,cond),xs)
def takewhile(cond,xs):
    for x in xs:
        if not cond(x): return
        yield x
def dropwhile(cond,xs):
    it = iter(xs)
    for x in it:
        if not cond(x):
            yield x
            break
    yield from it
def takeuntil(cond,xs):
    for x in xs:
        yield x
        if cond(x): return
takeWhile = lambda cond,xs: list(takewhile(cond,xs))
dropWhile = lambda cond,xs: list(dropwhile(cond,xs))
inits = lambda xs: [xs[:i] for i in range(len(xs) + 1)]
tails = lambda xs: [xs[i:] for i in range(len(xs) + 1)]
def chunksOf(n,xs):
    xs = list(xs)
    return [xs[i:i + n] for i in range(0,len(xs),n)]
def windows(n,xs):
    xs = list(xs)
    return [xs[i:i + n] for i in range(len(xs) - n + 1)]
def groupBy(eq,xs):
    out = []
    for x in xs:
        if out and eq(out[-1][0],x): out[-1].append(x)
        else: out.append([x])
    return out
group = partial(groupBy,eq)
def transpose(rows):
    rows = [list(r) for r in rows]
    out, i = [], 0
    while any(i < len(r) for r in rows):
        out.append([r[i] for r in rows if i < len(r)])
        i += 1
    return out
# 10. sorting & searching
sortOn = lambda f,xs: sorted(xs,key=f)
sortBy = lambda cmp,xs: sorted(xs,key=cmp_to_key(cmp))
maxOn = lambda f,xs: max(xs,key=f)
minOn = lambda f,xs: min(xs,key=f)
merge = lambda a,b: list(_hmerge(a,b))
# 11. strings
lines = str.splitlines
unlines = lambda ls: "".join(l + "\n" for l in ls)
words = str.split
unwords = " ".join
# 12. containers
def fromListWith(f,pairs):
    d = {}
    for k, v in pairs:
        d[k] = f(v,d[k]) if k in d else v
    return d
insertWith = lambda f,k,v,d: {**d, k: f(v,d[k]) if k in d else v}
unionWith = lambda f,a,b: {k: f(a[k],b[k]) if k in a and k in b else a[k] if k in a else b[k]
                           for k in a.keys() | b.keys()}
def getpath(t,ks,default=NOTHING):
    for k in ks:
        if not isinstance(t,dict) or k not in t: return default
        t = t[k]
    return t
bag_diff = lambda a,b: {k: a[k] - b.get(k,0) for k in a if a[k] > b.get(k,0)}
bag_inter = lambda a,b: {k: v for k in a.keys() & b.keys() if (v := min(a[k],b[k]))}
bag_union = lambda a,b: {k: max(a.get(k,0),b.get(k,0)) for k in a.keys() | b.keys()}
bag_sub = lambda a,b: all(b.get(k,0) >= n for k,n in a.items())
# 13. Maybe
bind = lambda x,f: NOTHING if x is NOTHING else f(x)
isJust = lambda x: x is not NOTHING
isNothing = lambda x: x is NOTHING
fromMaybe = lambda default,x: default if x is NOTHING else x
listToMaybe = lambda xs: xs[0] if xs else NOTHING
maybeToList = lambda x: [] if x is NOTHING else [x]
catMaybes = lambda xs: [x for x in xs if x is not NOTHING]
mapMaybe = lambda f,xs: [y for y in map(f,xs) if y is not NOTHING]
def sequenceM(xs):
    out = []
    for x in xs:
        if x is NOTHING: return NOTHING
        out.append(x)
    return out
traverseM = lambda f,xs: sequenceM(map_(f,xs))
maybe_get = lambda d,k: d.get(k,NOTHING)
# 14. Either
Ok = lambda v: ("ok", v)
Err = lambda e: ("err", e)
bindE = lambda x,f: x if x[0] == 'err' else f(x[1])
def sequenceE(xs):
    out = []
    for x in xs:
        if x[0] == "err": return x
        out.append(x[1])
    return Ok(out)
traverseE = lambda f,xs: sequenceE(map_(f,xs))
def partitionEithers(xs):
    oks, errs = [], []
    for tag, v in xs:
        (oks if tag == "ok" else errs).append(v)
    return (oks, errs)
note = lambda msg,x: Err(msg) if x is NOTHING else Ok(x)
# 15. do-notation
def do(binder,unit):
    def deco(gen_fn):
        def run(*a,**kw):
            g = gen_fn(*a,**kw)
            def step(val):
                try:
                    m = g.send(val)
                except StopIteration as e:
                    return unit(e.value)
                return binder(m,step)
            return step(None)
        return run
    return deco
doM = do(bind,identity)
doE = do(bindE,Ok)
# 16. parser combinators
def doP(gen_fn):
    def make(*a,**kw):
        def parser(s):
            g, val = gen_fn(*a,**kw), None
            try:
                while True:
                    r = g.send(val)(s)
                    if r is FAIL: return FAIL
                    val, s = r
            except StopIteration as e:
                return (e.value, s)
        return parser
    return make
alt = lambda *ps: lambda s: next((r for r in (p(s) for p in ps) if r is not FAIL),FAIL)
def many(p):
    def parser(s):
        out = []
        while (r := p(s)) is not FAIL and r[1] != s:
            out.append(r[0]); s = r[1]
        return (out, s)
    return parser
def many1(p):
    def parser(s):
        r = p(s)
        if r is FAIL: return FAIL
        rest = many(p)(r[1])
        return ([r[0]] + rest[0], rest[1])
    return parser
def sepBy(p,sep):
    def pair(s):
        r = sep(s)
        return FAIL if r is FAIL else p(r[1])
    def parser(s):
        r = p(s)
        if r is FAIL: return ([], s)
        rest = many(pair)(r[1])
        return ([r[0]] + rest[0], rest[1])
    return parser
def lit(c):
    def parser(s):
        s = s.lstrip()
        return (c, s[1:]) if s[:1] == c else FAIL
    return parser
def rx(pat,conv=identity):
    r = _re.compile(pat)
    def parser(s):
        s = s.lstrip()
        m = r.match(s)
        return (conv(m.group()), s[m.end():]) if m else FAIL
    return parser
def chainl1(p,ops):
    opp = alt(*[lit(c) for c in ops])
    def parser(s):
        vr = p(s)
        while vr is not FAIL:
            op = opp(vr[1])
            if op is FAIL: return vr
            w = p(op[1])
            if w is FAIL: return vr
            vr = (ops[op[0]](vr[0],w[0]), w[1])
        return FAIL
    return parser
def runParser(p,s):
    r = p(s)
    if r is FAIL: return Err(f"no parse: {s!r}")
    if r[1].strip(): return Err(f"unconsumed input: {r[1].strip()!r}")
    return Ok(r[0])
# 17. monoids
Monoid = lambda empty,op: (empty, op)
mconcat = lambda m,xs: foldl(m[1],xs,m[0])
foldMap = lambda f,m,xs: mconcat(m,[f(x) for x in xs])
both = lambda m1,m2: Monoid((m1[0], m2[0]),
              lambda a,b: (m1[1](a[0],b[0]), m2[1](a[1],b[1])))
Sum = Monoid(0,add)
Product = Monoid(1,mul)
All = Monoid(True,lambda a,b: a and b)
Any = Monoid(False,lambda a,b: a or b)
MaxM = Monoid(float("-inf"),max)
MinM = Monoid(float("inf"),min)
ListM = Monoid([],add)
First = Monoid(NOTHING,lambda a,b: b if a is NOTHING else a)
Last = Monoid(NOTHING,lambda a,b: a if b is NOTHING else b)
