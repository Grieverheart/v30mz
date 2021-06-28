
if __name__ == '__main__':
    with open('microcode_8086.txt', 'r') as fp:
        aluops = set()
        for line in fp.readlines():
            optype = line[51]
            aluop = line[55:61].strip()
            if optype == '1':
                aluops.add(aluop.strip())

        print(aluops)
