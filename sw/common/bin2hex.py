import sys

with open(sys.argv[1], "rb") as f:
    data = f.read()
data += bytes(-len(data) % 4)
with open(sys.argv[2], "w") as f:
    f.writelines(
        f"{int.from_bytes(data[i : i + 4], 'little'):08x}\n"
        for i in range(0, len(data), 4)
    )
