#include "o3.h"
#include "gpio.h"
#include "systick.h"

#define LED_PIN 2
#define LED_PORT GPIO_PORT_E
#define BUTTON_PORT GPIO_PORT_B
#define BUTTON_PIN 9

#define SECONDS_STATE 0
#define MINUTES_STATE 1
#define HOURS_STATE 2
#define COUNTDOWN_STATE 3
#define ALARM_STATE 4

/**************************************************************************//**
 * @brief Konverterer nummer til string 
 * Konverterer et nummer mellom 0 og 99 til string
 *****************************************************************************/
void int_to_string(char *timestamp, unsigned int offset, int i) {
    if (i > 99)                                     // kan maksimalt vises et tall med to siffer, altså er 99 maks
    {
        timestamp[offset]   = '9';
        timestamp[offset+1] = '9';                  // offset er posisjonen til tallet i en string (array av chars) som har 7 elementer
        return;
    }

    while (i > 0)
    {
	    if (i >= 10)
	    {
		    i -= 10;
		    timestamp[offset]++;
		
	    } else
	    {
		    timestamp[offset+1] = '0' + i;			// string pluss et heltall blir at man plusser på stringen
		    i=0;
	    }
    }
}

/**************************************************************************//**
 * @brief Konverterer 3 tall til en timestamp-string
 * timestamp-argumentet mÃ¥ vÃ¦re et array med plass til (minst) 7 elementer.
 * Det kan deklareres i funksjonen som kaller som "char timestamp[7];"
 * Kallet blir dermed:
 * char timestamp[7];
 * time_to_string(timestamp, h, m, s);
 *****************************************************************************/
void time_to_string(char *timestamp, int h, int m, int s) {
    timestamp[0] = '0';
    timestamp[1] = '0';
    timestamp[2] = '0';
    timestamp[3] = '0';
    timestamp[4] = '0';
    timestamp[5] = '0';
    timestamp[6] = '\0';

    int_to_string(timestamp, 0, h);
    int_to_string(timestamp, 2, m);
    int_to_string(timestamp, 4, s);
}

typedef struct
{
	volatile word CTRL;
	volatile word MODEL;
	volatile word MODEH;
	volatile word DOUT;
	volatile word DOUTSET;
	volatile word DOUTCLR;
	volatile word DOUTTGL;
	volatile word DIN;
	volatile word PINLOCKN;
} gpio_port_map_t;


typedef struct
{
	volatile gpio_port_map_t port[6];
	volatile word unused_space[10];
	volatile word EXTIPSELL;
	volatile word EXTIPSELH;
	volatile word EXTIRISE;
	volatile word EXTIFALL;
	volatile word IEN;
	volatile word IF;
	volatile word IFS;
	volatile word IFC;
	volatile word ROUTE;
	volatile word INSENSE;
	volatile word LOCK;
	volatile word CTRL;
	volatile word CMD;
	volatile word EM4WUEN;
	volatile word EM4WUPOL;
	volatile word EM4WUCAUSE;
} gpio_map_t;

typedef struct
{
	volatile word CTRL;
	volatile word LOAD;
	volatile word VAL;
} systick_map;

// ----- Globale konstanter -----
volatile gpio_map_t* GPIO_map;							// GPIO_map er en peker av typen gpio_map_t
int seconds, minutes, hours;
int state;

// ----- Set LED -----
void set_LED(int light)
{
	if(light == 1)
	{
		GPIO_map->port[LED_PORT].DOUTSET = 0b0100;		// pin 2 er LED-en. Setter dens verdi til 1. Bruker DOUTSET som OR-er for meg, så kun denne verdien endres
		//volatile word* LED_output = GPIO_map->port[LED_PORT].DOUTSET;
		//*LED_output = 0b0100;
	}
	else
	{
		GPIO_map->port[LED_PORT].DOUTCLR = 0b0100;		// setter CLEAR til å være 1 på LED sin port
	}
}


//----- PB1 interrupt handler -----
void GPIO_EVEN_IRQHandler(void) 						// sier hva som skal skje ved et EVEN interrupt. Det er altså når PB1 trykkes
{														// her skal vi toggle mellom de ulike statesene
    switch (state)
    {
        case HOURS_STATE:
            if(hours + minutes + seconds == 0) 			// hvis vi er i HOURS_STATE og tiden er 0 skal alarmen gå
            {
                state = ALARM_STATE;					// setter staten til neste state, som er ALARM_STATE (kunne vel egt inkrementert)
                set_LED(1);
            }
            else
            {
                state++;
            }
            break;
        case ALARM_STATE:								// alarmen har gått og knappen har blitt trykket igjen. Da skal vi gå til SECONDS_STATE
            state = SECONDS_STATE;
            set_LED(0);									// lyset skrus av
            break;
        case COUNTDOWN_STATE:							// ingenting skal skje om man trykker på knappen mens
            break;
        default:										// ved enten SECONDS_STATE, MINUTES_STATE skal staten bare inkrementeres
            state++;
    };

    GPIO_map->IFC = 1<<10;								// 1 left-shiftet med 10, som er pinen til PB1. Interrupt Flag Clear Register, clearer pin 10, som vil si at jeg sier at interruptet har skjedd og vi er klare for et nytt interrupt.
}


//----- PB0 interrupt handler -----						// sier hva som skal skje når PB0 trykkes
void GPIO_ODD_IRQHandler(void)
{
	//set_LED(1);										// brukte dette for å få lyset til å lyse når jeg trykket på knapp 0
    switch (state)
    {
        case SECONDS_STATE:								// hvis vi er i SECONDS_STATE og knapp 0 trykkes, skal sekundene inkrementeres
            seconds++;
            break;
        case MINUTES_STATE:								// minuttene skal inkrementeres
            minutes++;
            break;
        case HOURS_STATE:								// timene skal inkrementeres
            hours++;
            break;
    };

    GPIO_map->IFC = 1<<9;								// clearer interrupt flagget til pin 9
}

// ----- SysTick handler -----
void SysTick_Handler(void)								// det skal skje et interrupt når telleregisteret VAL har blitt 0, som jeg vil skal skje en gang hvert sekund
{
	switch(state)
	{
		case COUNTDOWN_STATE:
		{
			seconds--;
			if(hours == 0 && minutes == 0 && seconds == 0)
			{
				state = ALARM_STATE;
				set_LED(1);
			}
			if(seconds == -1)							// seconds var 0, og jeg trakk fra, det betyr at minuttene må trekkes fra
			{
				minutes--;
				seconds = 59;
				if(minutes == -1)						// hvis minutes nå er -1, så skal egt minutes være 59 og hours må trekkes fra
				{
					hours--;
					minutes = 59;
				}
			}
		}
	}
}



int main(void)
{
    init();
    GPIO_map = (gpio_map_t*) GPIO_BASE;										// GPIO_map er GPIO_BASE

    // ----- SysTick setup -----
    volatile systick_map* sys;
    sys = (systick_map*) SYSTICK_BASE;
    sys->CTRL = 0b0111;
    sys->LOAD = FREQUENCY;
    
    /*
    ~ invert
    & AND
    | OR
	*/

    // ----- Nå må jeg sette MODE på knappene og LED0 fordi dette ikke gjøres for meg  som på de andre øvingene -----

    // ----- Setter LED0 til output
    GPIO_map->port[LED_PORT].DOUT = 0;											// setter output LED0 til 0, så den ikke lyser fra start
    GPIO_map->port[LED_PORT].MODEL = ((~(0b1111 << 8))&GPIO_map->port[LED_PORT].MODEL)|(GPIO_MODE_OUTPUT << 8); 			// MODEL fordi LED0 er på pin 2. MODEL er pin 0-7, MODEH er pin 8-15. LSL-er 8 fordi da shifter jeg forbi pin 0 og pin 1.

    // ----- Setter PB0 til input -----
    GPIO_map->port[BUTTON_PORT].MODEH = ((~(0b1111 << 4))&GPIO_map->port[BUTTON_PORT].MODEH)|(GPIO_MODE_INPUT << 4);		// LSL 4 for å shifte over pin 8. MODEH fordi vi skal ha pin 9 (og 10 på neste knapp)

    // ----- Setter PB1 til input -----
    GPIO_map->port[BUTTON_PORT].MODEH = ((~(0b1111 << 8))&GPIO_map->port[BUTTON_PORT].MODEH)|(GPIO_MODE_INPUT << 8);		// LSL 8 for å shifte over pin 8 og pin 9


    // ----- PB0 interrupt setup -----
    GPIO_map->EXTIPSELH = ((~(0b1111))&GPIO_map->EXTIPSELH)|(0b0001 << 4);		// interrupts på pin 9 skal skje på PORT_B. Setter pin 9 til PORT_B fordi det er verdien til PORT_B (0001 = 1). PORT_A er 0 og PORT_C er 2 f.eks.
    GPIO_map->EXTIFALL = (GPIO_map->EXTIFALL)|(1<<9);							// interrupts skal se på falling edge, når det går fra høy til lav, altså når knappen trykkes inn
    GPIO_map->IFC = (GPIO_map->IFC)|(1<<9);										// for sikkerhets skyld clearer jeg interrupt-flagget på pin 9
    GPIO_map->IEN = (GPIO_map->IEN)|(1<<9);										// enabler interruptet. Nå vil interruptet til pin 9 kalles hver gang INPUT pin 9 på PORT_B går fra 1 til 0 (når knappen trykkes). Handleren blir kalt på


    // ----- PB1 interrupt setup -----
    GPIO_map->EXTIPSELH = ((~(0b1111))&GPIO_map->EXTIPSELH)|(0b0001 << 8);		// interrupts på pin 10 skal skje på PORT_B. Setter pin 10 til PORT_B fordi det er verdien til PORT_B (0001 = 1). PORT_A er 0 og PORT_C er 2 f.eks.
    GPIO_map->EXTIFALL = (GPIO_map->EXTIFALL)|(1<<10);							// interrupts skal se på falling edge, når det går fra høy til lav, altså når knappen trykkes inn
    GPIO_map->IFC = (GPIO_map->IFC)|(1<<10);									// for sikkerhets skyld clearer jeg interrupt-flagget på pin 10
    GPIO_map->IEN = (GPIO_map->IEN)|(1<<10);									// enabler interruptet. Nå vil interruptet til pin 10 kalles hver gang INPUT pin 10 på PORT_B går fra 1 til 0 (når knappen trykkes). Handleren blir kalt på


    // ----- Initialverdier -----
    seconds = 0;
    minutes = 0;
    hours = 0;
    state = SECONDS_STATE;

    while(1)
    {
    	char time[7];
        time_to_string(time, hours, minutes, seconds);
        lcd_write(time);
    }

    return 0;
}


// Droppet dette
// ----- Setter BUTTON OUTPUT til 0 -----	// trenger jeg dette? tror kanskje ikke det
//GPIO_map->port[BUTTON_PORT].DOUT = 0;

