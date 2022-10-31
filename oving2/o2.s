
.thumb
.syntax unified

.include "gpio_constants.s"     // Register-adresser og konstanter for GPIO
.include "sys-tick_constants.s" // Register-adresser og konstanter for SysTick

.text
	.global Start


// ----- Funksjon for å inkrementere tenths -----
Count_tenths:
	LDR R1, =tenths								// R1 er minneadressen til tenths
	LDR R0, [R1]								// R0 er verdien til tenths
	CMP R0, #9									// Sjekker om R0 (tenths) er 9
	BNE Increment_tenths 						// Hvis R0 er lik 9, altså hvis tenths er 9, så må den nullstilles. Vi går rett videre i koden. Hvis R0 ikke er 9, så hopper vi til False, og da øker vi tenths med 1

	Reset_tenths:								// Å kalle denne "seksjonen" for "Reset_tenths" (eller noe i det hele tatt) er egt ikke nødvendig, men gjør det for oversiktens skyld
		LDR R2, =#0								// Setter R2 til 0
		STR R2, [R1]							// Setter verdien til R1, altså verdien til tenths, til å være lik R2, som er 0. Har nå nullstilt tenths
		PUSH {LR}
		BL Count_seconds						// Hopper til Count_seconds, fordi nå som tiendelene har gått over 9, må seconds inkrementeres
		POP {LR}
		B End_tenths

	Increment_tenths:
		LDR R2, =#1
		ADD R0, R0, R2
		STR R0, [R1]

	End_tenths:
		MOV PC, LR								// Returnerer til der jeg var i koden

// ----- Funksjon for å inkrementere seconds -----
Count_seconds:
	// ----- Toggler LED0 -----
	LDR R3, =GPIO_BASE + LED_PORT*PORT_SIZE		// R3 er adressen til PORT_E
	LDR R4, =GPIO_PORT_DOUTTGL					// R4 er offsett til DOUTTGL PORT_E
	ADD R4, R3, R4								// R4 er nå adressen til DOUTTGL PORT_E

	MOV R6, #1
	LSL R6, R6, #LED_PIN						// Lager et binært tall som er 1 kun på plassen til LED_PIN

	STR R6, [R4]								// bruker DOUTTGL ved å sette den lik 1 på LED_PIN. Da vil LED_PIN bli togglet, altså satt til det motsatte av hva den var


	// ----- Fikser seconds -----
	LDR R1, =seconds							// Henter adressen til seconds
	LDR R0, [R1]								// Setter R0 til å være verdien til seconds
	CMP R0, #59									// Sjekker om seconds er lik 59
	BNE Increment_seconds						// Hvis seconds ikke er lik 59, så hopper koden ned til Increment_seconds

	Reset_seconds:
		LDR R2, =#0								// Setter R2 til å være 0
		STR R2, [R1]							// Setter seconds til å være lik R2, altså 0
		PUSH {LR}
		BL Count_minutes						// Må nå telle minutter
		POP {LR}
		B End_seconds

	Increment_seconds:
		LDR R2, =#1
		ADD R0, R0, R2
		STR R0, [R1]

	End_seconds:
		MOV PC, LR								// dette betyr bare "return"

// ----- Funksjon for å inkrementere minutes -----
Count_minutes:
	LDR R1, =minutes
	LDR R0, [R1]
	CMP R0, #59
	BNE Increment_minutes

	Reset_minutes:
		LDR R2, =#0
		STR R2, [R1]
		B End_minutes

	Increment_minutes:
		LDR R2, =#1
		ADD R0, R0, R2
		STR R0, [R1]

	End_minutes:
		MOV PC, LR


// ----- SysTick interrupt handler -----
.global SysTick_Handler
.thumb_func
		SysTick_Handler:						// Det skal skje et interrupt hver gang telleregisteret (VAL) blir 0. Dette interruptet skal telle tideler (tenths)
		PUSH {LR}
		BL Count_tenths
		POP {LR}
		BX LR									// Returnerer fra interruptet


// ----- Interrupt-oppsett for GPIO -----
.global GPIO_ODD_IRQHandler
.thumb_func
	GPIO_ODD_IRQHandler:						// Det skal skje et interrupt hver gang knappen trykkes
	LDR R0, =SYSTICK_BASE
	LDR R1, [R0]								// R1 er verdien til SysTick CTRL
	AND R1, #1									// ANDer tallet fra CTRL med 00001. Dette betyr at alle bit utenom det siste uansett er 0
	CMP R1, #0									// Sjekker om CTRL i SysTick har 1 på bit 0 (bittet lengst til høyre). Hvis R1 nå er lik 0, så var R1 0 på det siste bitet, som betyr at klokka var av, og vi må starte den
	BNE Stop_clock								// Hvis CTRL er 1 på bit 0, da går klokka, og da skal vi stoppe klokka

	Start_clock:
		LDR R1, =#0b111
		STR R1, [R0]
		B Clock_end

	Stop_clock:
		LDR R1, =#0b110							// Stopper klokka ved å sette CTRL til å være 110
		STR R1, [R0]							// R0 er adressen til SysTick, som også er adressen til det første registeret i SysTick, nemlig CTRL
		B Clock_end

	Clock_end:
		LDR R0, =GPIO_BASE
		LDR R1, =GPIO_IFC						// interrupt flag clear register
		LDR R2, =#1
		LSL R2, R2, #BUTTON_PIN					// Lager et binært tall som er 1 kun på pin 9 (BUTTON_PIN)
		STR R2, [R0, R1]						// GPIO_IFC har nå fått verdien 0b001000000000. CLEAR-registeret gjør at IF-registeret nullstilles (settes til 0) på den biten hvor det er 1. Vi gjør dette for å si fra at interruptet har blitt behandlet
		BX LR									// Returnerer fra interrupt


// ----- Start -----
Start:
	// ----- Setter opp SysTick -----
	LDR R3, =SYSTICK_BASE						// R3 er adressen til SysTick_BASE som også er CTRL-registeret
	LDR R4, =#110								// Setter riktige verdier på CTRL-registeret. 111 fordi det står i kompendiet under SysTick->CTRL. Må ha 111 her for at den skal begynne
	STR R4, [R3]
	LDR R5, =SYSTICK_LOAD						// Finner offsettet til SysTick LOAD
	LDR R6, =FREQUENCY/10						// Interrupt-frekvensen skal være så det interruptes hvert 0,1 sek
	STR R6, [R3, R5]							// Setter LOAD (BASE + LOAD) til riktig interrupt-frekvens, som er R6

	// ----- Setter klokka til 0 -----
	LDR R4, =#0
	LDR R6, =tenths
	STR R4, [R6]								// Verdien til tenths settes til 0

	// ----- Button interrupt setup -----
	LDR R0, =GPIO_BASE
	LDR R1, =GPIO_EXTIPSELH
	ADD R4, R0, R1								// R4 er adressen til EXTIPSELH
	LDR R2, =#0b1111							// Lager et tall som er 1111
	LSL R2, R2, #4								// Left-shifter dette tallet med 4. Da er pin 9 sine 4 bit alle 1, mens alt annet er 0
	MVN R2, R2									// Logisk bitvis NOT-operasjon. Dette gjør at alle tallene på pin 9 er 0, mens på pin 8 er alle bitene 1
	LDR R3, [R4]								// Setter R3 til å være verdien til EXTIPSELH
	AND R3, R2, R3								// ANDer verdien til EXTIPSELH med tallet som er 0 på alle bitene på pin 9 og 1 ellers. Dette gjør at vi nullstiller pin 9, mens alt annet forblir uforandret
	LDR R2, =#0b0001
	LSL R2, R2, #4								// Lager et tall som er 0001 0000
	ORR R2, R2, R3								// ORer det tallet^ med det nullstilte EXTIPSELH-tallet. Dette gjør at alt forblir det samme, utenom pin 9, som endres fra 0000 til 0001
	STR R2, [R0, R1]							// Setter den nye verdien til EXTIPSELH til å være det nye tallet som er 0001 på pin 9. Da har vi altså sagt at vi skal ha et interrupt på denne pinnen.
	// Nå skal vi ha en interrupt på pin 9 og port 0001, som er den andre porten, nemlig PORT_B


	// ----- Setter falling edge button -----	// Vi vil ha et interrupt på knappen når verdien går fra 1 til 0, fordi det er da knappen trykkes. Knappen er logisk høy når den ikke er trykket og logisk lav når den trykkes inn
	LDR R1, =GPIO_EXTIFALL
	LDR R4, [R0, R1]							// R4 er verdien til GPIO_EXTIPSELH
	LDR R2, =#1
	LSL R2, R2, #BUTTON_PIN
	ORR R4, R2, R4								// ORer verdien til EXTIPSELH med 001000000000. Dette betyr at det eneste som har endret seg er at pin 9 nå er 1
	STR R4, [R0, R1]							// Setter verdien til EXTIPSELH til å være lik R4. Nå har vi altså angitt at det skal skje interrupt på pin 9 ved Falling Edge
	// Nå vil vi få et inetrrupt når knappen trykkes inn (går fra høy til lav)


	// ----- Setter interrupt enable button -----
	LDR R1, =GPIO_IEN
	LDR R4, [R0, R1]
	ORR R4, R2, R4								// Bruker tallet 1000000000 som vi lagde på R2 i sted
	STR R4, [R0, R1]							// Den nye verdien til GPIO_IEN er nå 1 på pin 9. Det betyr at interrupt-vektoren som hører til pin 9 kalles hver gang verdien til pin 9 på PORT_B går fra 1 til 0, altså når den trykkes
	// Nå skal interruptet kalles hver gang knappen trykkes


	// ----- Setter IF til 0 ved å sette IFC til 1 -----
	LDR R1, =GPIO_IFC
	LDR R2, =#1
	LSL R2, R2, #BUTTON_PIN
	STR R2, [R0, R1]							// Setter pin 9 på IFC til å være 1, som betyr at vi clearer den og setter den til 0

	Loop:
		B Loop


NOP // Behold denne på bunnen av fila


// ----- Notes -----
/*
	tenths, seconds og minutes er minneadresser som "peker" på verdiene til klokka. Verdiene er de tallene som vises
	Når det står 00-00-1 er verdiene som følger:
	- minutes = 0
	- seconds = 0
	- tenths = 1
*/

// --------------- Testing ---------------

/*
// ----- Toggler det andre lyset -----
	LDR R3, =GPIO_BASE + LED_PORT*PORT_SIZE
	LDR R4, =GPIO_PORT_DOUTTGL
	ADD R4, R3, R4
	MOV R5, #1
	LSL R5, R5, #3
	STR R5, [R4]
*/


/*
// ----- Dette gjør at klokka starter når knappen trykkes -----
	// ----- Fikser knapp -----
	LDR R7, =GPIO_BASE + BUTTON_PORT*PORT_SIZE 	// R7 er adressen til PORT_B
	LDR R8, =GPIO_PORT_DIN
	ADD R8, R7, R8								// R8 er DIN PORT_B

	MOV R9, #1
	LSL R9, R9, #BUTTON_PIN						// Lager et binært tall som er 1 kun på pin 9


	// ----- Må sette SysTick CTRL til 111 når knappen trykkes -----

	Loop:
		LDR R10, [R8]							// R8 er verdien til DIN PORT_B
		AND R10, R10, R9						// R10 er nå ANDet med det binære tallet som kun er 1 på pin 9
		CMP R10, #0								// Sammenligner R10 med 0. R10 er 0 hvis knappen er trykket fordi knappen har verdi logisk lav når den er trykket
		BNE Not_pressed

		Pressed:
			LDR R4, =#111
			STR R4, [R3]
			B Loop

		Not_pressed:
			B Loop

*/

	// ----- Setter tenths til 1 -----
/*
	// Eller øker tenths med 1
	// Nå er jo tenths 0, og jeg øker den med 1, så da blir tenths = 1
    LDR R1, =tenths		// henter minneadressen til tenths
    LDR R0, [R1]		// setter R0 til å være verdien til R1, som er adressen til tenths. Altså R0 er nå verdien til tenths
    LDR R2, =#1			// setter R2 til å være 1

    ADD	R0, R0, R2		// adder R0 (verdien til tenths) og R2 (verdi 1)
    STR R0, [R1]		// setter verdien til R1, som også er verdien til tenths, til å være R0, som er "gamle" verdien til tenths + 1
    // det jeg egentlig har gjort her er å inkrementere verdien til tenths
*/


	// ----- Teller fra 0 til 9  på tenths (på sånn 0 sek...)-----
/*
	Loop:
	LDR R1, =tenths
    LDR R0, [R1]
    CMP R0, #9
    BNE False
    True:
    	B EndIf
    False:
    	LDR R2, =#1
    	ADD R0, R0, R2
    	STR R0, [R1]
    	B Loop
    EndIf:
*/
