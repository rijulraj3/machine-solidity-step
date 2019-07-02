
# Cartesi RISC-V Solidity Emulator

Cartesi RISC-V Solidity Emulator is the on-chain host implementation of the Cartesi Machine Specification. The libraries and contract are written in Solidity, the migration script in Javascript - with the help of [Truffle](https://github.com/trufflesuite/truffle) and the testing scripts in Python.

For Cartesi design to work, this implementation must have the exact transition function as the off-chain [Cartesi RISC-V Emulator](https://github.com/cartesi/core), meaning that if given the same initial state (s[i]) both implementation's step functions should reach a bit by bit consistent state s[i + 1].

Since the cost of storing a full Cartesi Machine state within the blockchain is prohibitive, all machine states are represented in the blockchain as cryptographic hashes. The content of those states and memory represented by those hashes are only known off-chain.

Cartesi uses Merkle trees operations and properties to ensure blockchain's implementation ability to correctly verify a state transition without full state-access. However, RISC-V Solidity emulator abstracts those operations and acts as if it knew the full contents of a machine state - using Memory Manager interface to fetch or write any necessary word on memory.

## Memory Manager

The memory manager contract is consumed by the RISC-V Solidity emulator as if the entire state content was available - since the off and on-chain emulators match down to the order in which accesses are logged. When a dispute arises, Alice sends her off-chain state access log referent to the disagreement step to the MemoryManager contract, which will guide the execution of a Step (i.e state transition function).

The MemoryManager contract offers the RISC-V Solidity emulator a very simple interface that consists of:

* read - reads a word in a specific address.
* write - writes a word in a specific address.
* finishReplayPhase - signals that the Step has completed.

It also makes sure that all accesses performed by the Step function match the ones provided by Alice and are consistent with the Merkle proofs provided by her. If that is not the case, Alice loses the dispute.

The real Memory Manager contract can be found at [contracts repo](https://github.com/cartesi/contracts). In the present repo we have a MockMemoryManager, that still offers the same interface and makes sure all the proofs are consistent - but it doesn't comply with the Verification Game requirements. It should not be used in production, it doesn't include security measures, it doesn't provide access control and so on. The MockMemoryManager is meant to be used for testing purposes, so that the state transition function can be tested without the need to play a full mock verification game.

## Step function

Step is the previously mentioned state transition function, it is meant to take the machine from state s[i] to state[i + 1], using the memory manager as an assistant. The step function receives a MemoryManager index - which should have been populated with the access log generated by the emulator off-chain and returns an Exit code signaling the result of its execution.

The Step execution usually consists of the following steps:
- Check if machine is halted.
- If not, raise the highest priority interrupt (if there is any to be raised).
- Fetch instruction.
- If Fetch was successful, tries to execute that instruction.
- If Execute was successful updates the number of retired instructions.
- Updated the mcycle.
- End Step.

During a Step execution, every necessary read or write (be it to memory, registers etc) is processed and verified by the MemoryManager at the index provided in the function call.

## Getting Started

### Install

Install dependencies

    npm install

Compile contracts with

    ./node_modules/.bin/truffle compile

Having a node listening to 8545, you can deploy using

    ./node_modules/.bin/truffle deploy


### Run tests
Have an Ethereum node listening to port 8545
    ./node_modules/.bin/truffle deploy

Update data.json to match the access log of the step (or list of steps) that you would like to run.

    python test_python.py.


## Contributing

Pull requests are welcome. When contributing to this repository, please first discuss the change you wish to make via issue, email, or any other method with the owners of this repository before making a change.

Please note we have a code of conduct, please follow it in all your interactions with the project.

## Authors

* *Felipe Argento*

## License
[MIT](https://choosealicense.com/licenses/mit/)

