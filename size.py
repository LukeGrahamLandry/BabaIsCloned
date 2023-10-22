import os
import sys

if len(sys.argv) < 2:
    print("First arg should be path to executable.")
    exit(1)

print("Running objdump...")
process = os.popen("objdump -d " + sys.argv[1])
output = process.read()
result_flag = process.close()
exitcode = 0 if result_flag is None else result_flag >> 8

if exitcode != 0:
    print("objdump failed with exitcode=" + str(exitcode))
    exit(1)

print("Parsing...")
results = []
lines = output.splitlines()
i = 0
total = 0
while i < len(lines) - 1:
    line = lines[i]
    if not line.endswith(">:"):
        i += 1
        continue

    parts = line.split(" ")
    start_addr = int(parts[0], 16)
    # objective-c message passing calls have spaces in them. 
    name_start = len(parts[0]) + 2
    name = line[name_start:-2]
    if name.startswith("-"):
        name = name[1:]

    # This gets you to the last line of the function. 
    while len(line) != 0 and i < len(lines) - 1:
        prev_line = line
        i += 1
        line = lines[i]
    
    # Want to count to the end of the last instruction, not the start of it.
    # Instructions are 4 bytes. 
    parts = prev_line.split(":")
    end_addr = int(parts[0], 16) + 4

    # If that wasn't the last function, get to first line of next function. 
    # Don't need to do this because I know the instrction length. TODO: remove
    if i < len(lines) - 1:
        while len(line) == 0 or line.startswith("Disassembly"):
            i += 1
            line = lines[i]
        parts = line.split(" ")
        real_end_addr = int(parts[0], 16)
        if end_addr != real_end_addr:
            # This has never happened to me. 
            print("Guess was wrong")
        end_addr = real_end_addr

        # Next loop iter needs to read that function again. 
        i -= 1
        
    size = end_addr - start_addr
    results.append((size, name))
    i += 1
    total += size

results.sort(key=lambda x: x[0])

for func in results:
    print(str(func[0]) + ": " + func[1])
print("=======")
print("TOTAL: " + str(total) + " bytes.")
