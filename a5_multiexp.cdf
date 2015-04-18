/* Quartus II 64-Bit Version 14.0.2 Build 209 09/17/2014 SJ Full Version */
JedecChain;
	FileRevision(JESD32A);
	DefaultMfr(6E);

	P ActionCode(Cfg)
		Device PartName(5AGXFB3H4F35) Path("./build/") File("a5_multiexp.sof") MfrSpec(OpMask(1));
	P ActionCode(Ign)
		Device PartName(5M2210Z) MfrSpec(OpMask(0));

ChainEnd;

AlteraBegin;
	ChainType(JTAG);
AlteraEnd;
