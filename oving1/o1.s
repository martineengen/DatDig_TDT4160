.thumb
.syntax unified

.include "gpio_constants.s"     // Register-adresser og konstanter for GPIO

.text
	.global Start
	
Start:
	/*
	LDR R1, =GPIO_BASE + PORT_SIZE*LED_PORT + GPIO_PORT_DOUTSET
	LDR R3, =GPIO_BASE + PORT_SIZE*BUTTON_PORT + GPIO_PORT_DOUTSET
	*/

	// ----- Finner PORT_E ----- Her er LED
	LDR R0, =PORT_E // portnummer
	LDR R1, =PORT_SIZE // portregisterPerPort
	MUL R0, R0, R1 // portnummer * portstørrelse (9w = 36B)
	LDR R1, =GPIO_BASE // adressen til offset-et
	ADD R0, R0, R1 // adresse til PORT_E

	// ----- Finner LED adresse ----- byttet til DOUT fordi jeg velger å bruke en OR i while løkken også bruker jeg CLEAR og setter pin 2 til 1 på CLEAR fordi da settes DOUT til 0
	LDR R1, =GPIO_PORT_DOUT
	ADD R1, R0, R1

	// ----- Finner PORT_B ----- Her er Button
	LDR R2, =PORT_B // portnummer
	LDR R3, =PORT_SIZE // portregisterPerPort
	MUL R2, R2, R3 // portnummer * portstørrelse (9w = 36B)
	LDR R3, =GPIO_BASE // adressen til offset-et
	ADD R2, R2, R3 // adresse til PORT_B

	// ----- Finner BTN adresse -----
	LDR R3, =GPIO_PORT_DIN
	ADD R3, R2, R3

	// ----- Finner LED CLEAR -----
	LDR R7, =GPIO_PORT_DOUTCLR
	ADD R7, R7, R0

	// Lager nå to tall som er 1 på LED_PIN og BUTTON_PIN sin plass, henholdsvis pin 2 og pin 9

	// ----- Referanse til LED -----
	MOV R4, #1
	LSL R4, R4, #LED_PIN

	// ----- Referanse til BTN -----
	MOV R5, #1 					// setter R4 til å ha verdien 1 -> 000000000001
	LSL R5, R5, #BUTTON_PIN 	// left-shift, #BUTTON_PIN = 9 => R5 = 1000000000. Har altså left-shiftet R5 med 9 plasser

	// R0 = PORT_E
	// R1 = LED OUTPUT ADRESSE
	// R2 = PORT_B
	// R3 = BTN INPUT ADRESSE
	// R4 = 0b0000000100 -> LED REF
	// R5 = 0b1000000000 -> BTN REF
	// R7 = LED CLEAR

	// ----- While-løkke -----
	Loop:
		LDR R6, [R3]		// R6 = verdien til BTN INPUT
		AND R6, R6, R5		// ANDer BTN INPUT med BTN REF
		CMP R6, #0
		BNE False // Branch if Not Equal, gå til False

// Knappen er logisk lav, altså når den er presset, er pin 9 på DATA INPUT PORT_B = 0
		True:
			LDR R6, [R1]	// R6 = verdien til LED OUTPUT
			ORR R6, R6, R4	// ORer LED REF med LED OUTPUT, alle pinsene forblir det samme som de var, utenom LED OUTPUT, som blir 1 hvis den var 0. Forskjellen på DOUTSET og DOUT er at med DOUT må man ORe, mens med DOUTSET gjøres det automatisk
			STR R6, [R1]	// Setter verdien til det som ligger på adressen som er lagret i R1, altså DATA OUTPUT på PORT_B til å være R6, som nå har 1 på LED OUTPUT
			B Loop

		False:
			LDR R6, [R1]	// R6 er verdien LED OUTPUT -> et binært tall med en bit for hver pin
			// Hvis lyset er på, vil denne verdien være ...**1*
			STR R6, [R7]	// R7 = LED OUTPUT, altså LED_CLEAR er 1 på pin 2, som skal bety at LED-lyset burde CLEARes, og da altså slutte å lyse
			B Loop
			// Prøver CLEAR i stedet for å sette til 0
			//MOV R6, #0
			//STR R6, [R1]
			//B EndIf
		//EndIf:

	// BNE Loop


NOP // Behold denne på bunnen av fila



/* ----- Sjekker om R5 er lik 1000000000, og det er den -----
	CMP R5, 0b1000000000
	BNE else
		MOV R6, #1
		LSL R6, R6, #2
		LDR R7, =GPIO_PORT_DOUTSET
		STR R6, [R0, R7]
		B endif
	else:
		MOV R8, #1
		LSL R8, R8, #3
		LDR R9, =GPIO_PORT_DOUTSET
		STR R8, [R0, R9]
	endif:
*/

/*
	// Får lyset til å lyse konstant
	MOV R2, #1 // setter R2 til å ha verdien 1
	LSL R2, R2, #LED_PIN // left-shift, led_pin = 2
	LDR R1, =GPIO_PORT_DOUTSET // R2 settes til offset-verdien til data out set register
	STR R2, [R0, R1] // R0 + R1, som er data output set i port_E, får verdien 1 på plassen til LED_PIN

	Maks 12 register, ikke bruk R12 fordi det brukes til noe VIKTIG
*/



