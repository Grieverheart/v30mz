
if __name__ == '__main__':
    with open('microcode_8086.txt', 'r') as fp:
        src = set()
        dst = set()
        for line in fp.readlines():
            vals = line[32:51].split('->')
            if len(vals) == 2:
                src.add(vals[0].strip())
                dst.add(vals[1].strip())
            else:
                src.add('no dest')
                dst.add('no dest')

        print(sorted(sorted(src), key=len))
        print(sorted(sorted(dst), key=len))

        print(len(src), len(dst))
        print(len(src.union(dst)))

        print(len(src.intersection(dst)), sorted(sorted(src.intersection(dst)), key=len))
        print(len(dst.difference(src)), sorted(sorted(dst.difference(src)), key=len))
        print(len(src.difference(dst)), sorted(sorted(src.difference(dst)), key=len))
