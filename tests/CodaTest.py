
ceazor = ("0x3c5Aac016EF2F178e8699D6208796A2D67557fe2")
owner =  ("0x699675204aFD7Ac2BB146d60e4E3Ddc243843519")
Beets = Contract("0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e")
CRE8R = Contract("0x2aD402655243203fcfa7dCB62F8A08cc2BA88ae0")
USDC = Contract("0x04068DA6C83AFCFA0e13ba15A6696662335D5B75")
wFTM = Contract("0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83")
want = Contract("0xA1BfDf81eD709283C03Ce5C78B105f39FD7fE119")
gauge = Contract("0x8166994d9ebBe5829EC86Bd81258149B87faCfd3")

vault = CeazorVaultR.deploy(want, 'CRE8RCodaCompounder', 'ceazCRE8RCoda', {'from': owner})
strat = CRE8RelCoda.deploy(vault, {'from': owner})
vault.initialize(strat)
vault.addFren(ceazor, {'from': owner})

gauge.userInfo(100, ceazor)
gauge.withdrawAndHarvest(100, 214324154370168877928447, ceazor, {'from': ceazor})
want.approve(vault, 2**256-1, {'from': ceazor})

vault.depositAll({'from': ceazor})
chain.mine(3000)
tx = strat.harvest({'from': owner})


####DEPLOY####
vault = Contract("0x068D9D09DDC1Cf2b66A4C32eD74fFE68Db0b5f1B")
strat = Contract("0x7fF9e32C4D8359b19b7269220E73fb12Afa300C9")
owner => vault, strat
addFren(
ceazor = ("0x3c5Aac016EF2F178e8699D6208796A2D67557fe2")
hotwallet = ('0xA67D2c03c3cfe6177a60cAed0a4cfDA7C7a563e0')
)
