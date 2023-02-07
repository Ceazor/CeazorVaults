
ceazor = ("0x3c5Aac016EF2F178e8699D6208796A2D67557fe2")
owner =  ("0x699675204aFD7Ac2BB146d60e4E3Ddc243843519")
Beets = Contract("0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e")
CRE8R = Contract("0x2aD402655243203fcfa7dCB62F8A08cc2BA88ae0")
USDC = Contract("0x04068DA6C83AFCFA0e13ba15A6696662335D5B75")
wFTM = Contract("0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83")
want = Contract("0xA1BfDf81eD709283C03Ce5C78B105f39FD7fE119")

vault = CeazorVaultR.deploy(want, ceazCRE8RCoda, ceazCRE8RelCodaCompounder, {'from': owner})
strat = CRE8RelCoda.deploy(vault, {'from': owner})

chef = Contract('0x8166994d9ebBe5829EC86Bd81258149B87faCfd3')
chef.withdrawAndHarvest()
