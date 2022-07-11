from typing import Container


ceazor = ("0x3c5Aac016EF2F178e8699D6208796A2D67557fe2")
USDC = Contract("0x04068da6c83afcfa0e13ba15a6696662335d5b75")
hUSDC = Contract("0x243E33aa7f6787154a8E59d3C27a66db3F8818ee")

hUSDC.mint(5*10e5, {'from': ceazor})        #mints 5USDC worth of hUSDC
hUSDC.balanceOf(ceazor)                     #24761157803
hUSDC.redeem(24761157803, {'from': ceazor}) #redeems back to USDC

hUSDCtoLQDR = Contract('0x9a07fb107b9d8ea8b82ecf453efb7cfb85a66ce9')
hMIMtoLQDR = Contract('0xed566b089fc80df0e8d3e0ad3ad06116433bf4a7')
hFRAXtoLQDR = Contract('0x669F5f289A5833744E830AD6AB767Ea47A3d6409')
hDAItoLQDR = Contract('0x79364e45648db09ee9314e47b2fd31c199eb03b9')


