{	Copyright (C) 2024 Andrey Zubarev <zamtmn@yandex.ru>.

    Based on https://github.com/davidbannon/hunspell4pas

    License:
    This code is licensed under BSD 3-Clause Clear License, see file License.txt
    or https://spdx.org/licenses/BSD-3-Clause-Clear.html

    Note this unit 'includes' hunspell.inc that has a different license, please
    see that file for details.
}

unit uSpeller;
{$mode objfpc}{$H+}
{$ModeSwitch advancedrecords}
{$Codepage UTF8}

interface

uses
  SysUtils,FileUtil,Classes,
  gvector,
  uHunspell;

type

  TSymType=(STLowLetter,STUpLetter,STNotLetter);

  TSpeller=record
    private
      type
        TSpellerData=record
          Lang:string;
          Speller:THunspell;
        end;
        TSpellers=specialize TVector<TSpellerData>;

      var
        Spellers:TSpellers;
        LogProc:TLogProc;
    public
      type
        TLangHandle=integer;
        TSpellOpt=(SOFirstError,SOSuggest,SOCheckOneLetterWords);
        TSpellOpts=set of TSpellOpt;

      const
        CSpellOptFast=[SOFirstError];
        CSpellOptDetail=[SOSuggest];
        WrongLang=-1;
        MixedLang=-2;
        NoText=-3;
        CAbbrvDictName='abbrv';
    constructor CreateRec(ALogProc:TLogProc);
    procedure DestroyRec;
    function LoadDictionary(const DictName:string;const Lang:string=''):TLangHandle;
    procedure LoadDictionaries(Dicts:string);
    function SpellWord(Word:String;const CanBeAbbrv:boolean=false):TLangHandle;//>WrongLang if ok
    function SpellTextSimple(Text:String;out ErrW:string;Opt:TSpellOpts):TLangHandle;//>WrongLang or MixedLang or NoText if ok
    procedure Suggest(Word:string; List: TStrings);
  end;

implementation

function GetUtf8SymType(const sym:array of AnsiChar):TSymType;
var
  c2,c3:AnsiChar;
  OldChar:Word;
begin
  //какая херня(( надо по нормальному((
  case length(sym) of
    1:begin
      case sym[0] of
        'a'..'z':exit(STLowLetter);
        'A'..'Z':exit(STUpLetter);
        else
          exit(STNotLetter);
      end;
    end;
    2,3:begin
      case sym[0] of
        #$C3..#$C9, #$CE, #$CF, #$D0..#$D5, #$E1..#$E2,#$E5: begin
          c2:=sym[1];
          case sym[0] of
            #$C3: if c2 in [#$80..#$9E] then exit(STUpLetter);
            #$C4:begin
              case c2 of
                #$80..#$AF, #$B2..#$B6: if ord(c2) mod 2 = 0 then exit(STUpLetter);
                #$B8..#$FF: if ord(c2) mod 2 = 1 then exit(STUpLetter);
                #$B0: exit(STUpLetter);
              end;
            end;
            #$C5:begin
              case c2 of
                #$8A..#$B7: if ord(c2) mod 2 = 0 then exit(STUpLetter);
                #$00..#$88, #$B9..#$FF: if ord(c2) mod 2 = 1 then exit(STUpLetter);
                #$B8: exit(STUpLetter);
              end;
            end;
            // Process E5 to avoid stopping on chinese chars
            #$E5: if (c2 = #$BC) and (sym[2] in [#$A1..#$BA]) then exit(STUpLetter);
            // Others are too complex, better not to pre-inspect them
            else begin
              // Chars with 2-bytes which might be modified
              case sym[0] of
                #$C3..#$D5:begin
                  c2 := sym[1];
                  case sym[0] of
                  // Latin Characters 0000–0FFF http://en.wikibooks.org/wiki/Unicode/Character_reference/0000-0FFF
                  // codepoints      UTF-8 range           Description                Case change
                  // $00C0..$00D6    C3 80..C3 96          Capital Latin with accents X+$20
                  // $D7             C3 97                 Multiplication Sign        N/A
                  // $00D8..$00DE    C3 98..C3 9E          Capital Latin with accents X+$20
                  // $DF             C3 9F                 German beta ß              already lowercase
                  #$C3:
                  begin
                    case c2 of
                    #$80..#$96, #$98..#$9E: exit(STUpLetter)
                    end;
                  end;
                  // $0100..$012F    C4 80..C4 AF        Capital/Small Latin accents  if mod 2 = 0 then X+1
                  // $0130..$0131    C4 B0..C4 B1        Turkish
                  //  C4 B0 turkish uppercase dotted i -> 'i'
                  //  C4 B1 turkish lowercase undotted ı
                  // $0132..$0137    C4 B2..C4 B7        Capital/Small Latin accents  if mod 2 = 0 then X+1
                  // $0138           C4 B8               ĸ                            N/A
                  // $0139..$024F    C4 B9..C5 88        Capital/Small Latin accents  if mod 2 = 1 then X+1
                  #$C4:
                  begin
                    case c2 of
                      #$80..#$AF, #$B2..#$B7: if ord(c2) mod 2 = 0 then exit(STUpLetter);
                      #$B0: // Turkish
                        exit(STUpLetter);
                      #$B9..#$BE: if ord(c2) mod 2 = 1 then exit(STUpLetter);
                      #$BF: // This crosses the borders between the first byte of the UTF-8 char
                        exit(STUpLetter);
                    end;
                  end;
                  // $C589 ŉ
                  // $C58A..$C5B7: if OldChar mod 2 = 0 then NewChar := OldChar + 1;
                  // $C5B8:        NewChar := $C3BF; // Ÿ
                  // $C5B9..$C8B3: if OldChar mod 2 = 1 then NewChar := OldChar + 1;
                  #$C5:
                  begin
                    case c2 of
                      #$8A..#$B7: //0
                      begin
                        if ord(c2) mod 2 = 0 then
                          exit(STUpLetter);
                      end;
                      #$00..#$88, #$B9..#$BE: //1
                      begin
                        if ord(c2) mod 2 = 1 then
                          exit(STUpLetter);
                      end;
                      #$B8:  // Ÿ
                      begin
                        exit(STUpLetter);
                      end;
                    end;
                  end;
                  {A convoluted part: C6 80..C6 8F

                  0180;LATIN SMALL LETTER B WITH STROKE;Ll;0;L;;;;;N;LATIN SMALL LETTER B BAR;;0243;;0243
                  0181;LATIN CAPITAL LETTER B WITH HOOK;Lu;0;L;;;;;N;LATIN CAPITAL LETTER B HOOK;;;0253; => C6 81=>C9 93
                  0182;LATIN CAPITAL LETTER B WITH TOPBAR;Lu;0;L;;;;;N;LATIN CAPITAL LETTER B TOPBAR;;;0183;
                  0183;LATIN SMALL LETTER B WITH TOPBAR;Ll;0;L;;;;;N;LATIN SMALL LETTER B TOPBAR;;0182;;0182
                  0184;LATIN CAPITAL LETTER TONE SIX;Lu;0;L;;;;;N;;;;0185;
                  0185;LATIN SMALL LETTER TONE SIX;Ll;0;L;;;;;N;;;0184;;0184
                  0186;LATIN CAPITAL LETTER OPEN O;Lu;0;L;;;;;N;;;;0254; ==> C9 94
                  0187;LATIN CAPITAL LETTER C WITH HOOK;Lu;0;L;;;;;N;LATIN CAPITAL LETTER C HOOK;;;0188;
                  0188;LATIN SMALL LETTER C WITH HOOK;Ll;0;L;;;;;N;LATIN SMALL LETTER C HOOK;;0187;;0187
                  0189;LATIN CAPITAL LETTER AFRICAN D;Lu;0;L;;;;;N;;;;0256; => C9 96
                  018A;LATIN CAPITAL LETTER D WITH HOOK;Lu;0;L;;;;;N;LATIN CAPITAL LETTER D HOOK;;;0257; => C9 97
                  018B;LATIN CAPITAL LETTER D WITH TOPBAR;Lu;0;L;;;;;N;LATIN CAPITAL LETTER D TOPBAR;;;018C;
                  018C;LATIN SMALL LETTER D WITH TOPBAR;Ll;0;L;;;;;N;LATIN SMALL LETTER D TOPBAR;;018B;;018B
                  018D;LATIN SMALL LETTER TURNED DELTA;Ll;0;L;;;;;N;;;;;
                  018E;LATIN CAPITAL LETTER REVERSED E;Lu;0;L;;;;;N;LATIN CAPITAL LETTER TURNED E;;;01DD; => C7 9D
                  018F;LATIN CAPITAL LETTER SCHWA;Lu;0;L;;;;;N;;;;0259; => C9 99
                  }
                  #$C6:
                  begin
                    case c2 of
                      #$81:
                      begin
                        exit(STUpLetter);
                      end;
                      #$82..#$85:
                      begin
                        if ord(c2) mod 2 = 0 then
                          exit(STUpLetter);
                      end;
                      #$87..#$88,#$8B..#$8C:
                      begin
                        if ord(c2) mod 2 = 1 then
                          exit(STUpLetter);
                      end;
                      #$86:
                      begin
                        exit(STUpLetter);
                      end;
                      #$89:
                      begin
                        exit(STUpLetter);
                      end;
                      #$8A:
                      begin
                        exit(STUpLetter);
                      end;
                      #$8E:
                      begin
                        exit(STUpLetter);
                      end;
                      #$8F:
                      begin
                        exit(STUpLetter);
                      end;
                    {
                    And also C6 90..C6 9F

                    0190;LATIN CAPITAL LETTER OPEN E;Lu;0;L;;;;;N;LATIN CAPITAL LETTER EPSILON;;;025B; => C9 9B
                    0191;LATIN CAPITAL LETTER F WITH HOOK;Lu;0;L;;;;;N;LATIN CAPITAL LETTER F HOOK;;;0192; => +1
                    0192;LATIN SMALL LETTER F WITH HOOK;Ll;0;L;;;;;N;LATIN SMALL LETTER SCRIPT F;;0191;;0191 <=
                    0193;LATIN CAPITAL LETTER G WITH HOOK;Lu;0;L;;;;;N;LATIN CAPITAL LETTER G HOOK;;;0260; => C9 A0
                    0194;LATIN CAPITAL LETTER GAMMA;Lu;0;L;;;;;N;;;;0263; => C9 A3
                    0195;LATIN SMALL LETTER HV;Ll;0;L;;;;;N;LATIN SMALL LETTER H V;;01F6;;01F6 <=
                    0196;LATIN CAPITAL LETTER IOTA;Lu;0;L;;;;;N;;;;0269; => C9 A9
                    0197;LATIN CAPITAL LETTER I WITH STROKE;Lu;0;L;;;;;N;LATIN CAPITAL LETTER BARRED I;;;0268; => C9 A8
                    0198;LATIN CAPITAL LETTER K WITH HOOK;Lu;0;L;;;;;N;LATIN CAPITAL LETTER K HOOK;;;0199; => +1
                    0199;LATIN SMALL LETTER K WITH HOOK;Ll;0;L;;;;;N;LATIN SMALL LETTER K HOOK;;0198;;0198 <=
                    019A;LATIN SMALL LETTER L WITH BAR;Ll;0;L;;;;;N;LATIN SMALL LETTER BARRED L;;023D;;023D <=
                    019B;LATIN SMALL LETTER LAMBDA WITH STROKE;Ll;0;L;;;;;N;LATIN SMALL LETTER BARRED LAMBDA;;;; <=
                    019C;LATIN CAPITAL LETTER TURNED M;Lu;0;L;;;;;N;;;;026F; => C9 AF
                    019D;LATIN CAPITAL LETTER N WITH LEFT HOOK;Lu;0;L;;;;;N;LATIN CAPITAL LETTER N HOOK;;;0272; => C9 B2
                    019E;LATIN SMALL LETTER N WITH LONG RIGHT LEG;Ll;0;L;;;;;N;;;0220;;0220 <=
                    019F;LATIN CAPITAL LETTER O WITH MIDDLE TILDE;Lu;0;L;;;;;N;LATIN CAPITAL LETTER BARRED O;;;0275; => C9 B5
                    }
                    #$90:
                    begin
                      exit(STUpLetter);
                    end;
                    #$91, #$98: exit(STUpLetter);
                    #$93:
                    begin
                      exit(STUpLetter);
                    end;
                    #$94:
                    begin
                      exit(STUpLetter);
                    end;
                    #$96:
                    begin
                      exit(STUpLetter);
                    end;
                    #$97:
                    begin
                      exit(STUpLetter);
                    end;
                    #$9C:
                    begin
                      exit(STUpLetter);
                    end;
                    #$9D:
                    begin
                      exit(STUpLetter);
                    end;
                    #$9F:
                    begin
                      exit(STUpLetter);
                    end;
                    {
                    And also C6 A0..C6 AF

                    01A0;LATIN CAPITAL LETTER O WITH HORN;Lu;0;L;004F 031B;;;;N;LATIN CAPITAL LETTER O HORN;;;01A1; => +1
                    01A1;LATIN SMALL LETTER O WITH HORN;Ll;0;L;006F 031B;;;;N;LATIN SMALL LETTER O HORN;;01A0;;01A0 <=
                    01A2;LATIN CAPITAL LETTER OI;Lu;0;L;;;;;N;LATIN CAPITAL LETTER O I;;;01A3; => +1
                    01A3;LATIN SMALL LETTER OI;Ll;0;L;;;;;N;LATIN SMALL LETTER O I;;01A2;;01A2 <=
                    01A4;LATIN CAPITAL LETTER P WITH HOOK;Lu;0;L;;;;;N;LATIN CAPITAL LETTER P HOOK;;;01A5; => +1
                    01A5;LATIN SMALL LETTER P WITH HOOK;Ll;0;L;;;;;N;LATIN SMALL LETTER P HOOK;;01A4;;01A4 <=
                    01A6;LATIN LETTER YR;Lu;0;L;;;;;N;LATIN LETTER Y R;;;0280; => CA 80
                    01A7;LATIN CAPITAL LETTER TONE TWO;Lu;0;L;;;;;N;;;;01A8; => +1
                    01A8;LATIN SMALL LETTER TONE TWO;Ll;0;L;;;;;N;;;01A7;;01A7 <=
                    01A9;LATIN CAPITAL LETTER ESH;Lu;0;L;;;;;N;;;;0283; => CA 83
                    01AA;LATIN LETTER REVERSED ESH LOOP;Ll;0;L;;;;;N;;;;;
                    01AB;LATIN SMALL LETTER T WITH PALATAL HOOK;Ll;0;L;;;;;N;LATIN SMALL LETTER T PALATAL HOOK;;;; <=
                    01AC;LATIN CAPITAL LETTER T WITH HOOK;Lu;0;L;;;;;N;LATIN CAPITAL LETTER T HOOK;;;01AD; => +1
                    01AD;LATIN SMALL LETTER T WITH HOOK;Ll;0;L;;;;;N;LATIN SMALL LETTER T HOOK;;01AC;;01AC <=
                    01AE;LATIN CAPITAL LETTER T WITH RETROFLEX HOOK;Lu;0;L;;;;;N;LATIN CAPITAL LETTER T RETROFLEX HOOK;;;0288; => CA 88
                    01AF;LATIN CAPITAL LETTER U WITH HORN;Lu;0;L;0055 031B;;;;N;LATIN CAPITAL LETTER U HORN;;;01B0; => +1
                    }
                    #$A0..#$A5,#$AC:
                    begin
                      if ord(c2) mod 2 = 0 then
                        exit(STUpLetter);
                    end;
                    #$A7,#$AF:
                    begin
                      if ord(c2) mod 2 = 1 then
                        exit(STUpLetter);
                    end;
                    #$A6:
                    begin
                      exit(STUpLetter);
                    end;
                    #$A9:
                    begin
                      exit(STUpLetter);
                    end;
                    #$AE:
                    begin
                      exit(STUpLetter);
                    end;
                    {
                    And also C6 B0..C6 BF

                    01B0;LATIN SMALL LETTER U WITH HORN;Ll;0;L;0075 031B;;;;N;LATIN SMALL LETTER U HORN;;01AF;;01AF <= -1
                    01B1;LATIN CAPITAL LETTER UPSILON;Lu;0;L;;;;;N;;;;028A; => CA 8A
                    01B2;LATIN CAPITAL LETTER V WITH HOOK;Lu;0;L;;;;;N;LATIN CAPITAL LETTER SCRIPT V;;;028B; => CA 8B
                    01B3;LATIN CAPITAL LETTER Y WITH HOOK;Lu;0;L;;;;;N;LATIN CAPITAL LETTER Y HOOK;;;01B4; => +1
                    01B4;LATIN SMALL LETTER Y WITH HOOK;Ll;0;L;;;;;N;LATIN SMALL LETTER Y HOOK;;01B3;;01B3 <=
                    01B5;LATIN CAPITAL LETTER Z WITH STROKE;Lu;0;L;;;;;N;LATIN CAPITAL LETTER Z BAR;;;01B6; => +1
                    01B6;LATIN SMALL LETTER Z WITH STROKE;Ll;0;L;;;;;N;LATIN SMALL LETTER Z BAR;;01B5;;01B5 <=
                    01B7;LATIN CAPITAL LETTER EZH;Lu;0;L;;;;;N;LATIN CAPITAL LETTER YOGH;;;0292; => CA 92
                    01B8;LATIN CAPITAL LETTER EZH REVERSED;Lu;0;L;;;;;N;LATIN CAPITAL LETTER REVERSED YOGH;;;01B9; => +1
                    01B9;LATIN SMALL LETTER EZH REVERSED;Ll;0;L;;;;;N;LATIN SMALL LETTER REVERSED YOGH;;01B8;;01B8 <=
                    01BA;LATIN SMALL LETTER EZH WITH TAIL;Ll;0;L;;;;;N;LATIN SMALL LETTER YOGH WITH TAIL;;;; <=
                    01BB;LATIN LETTER TWO WITH STROKE;Lo;0;L;;;;;N;LATIN LETTER TWO BAR;;;; X
                    01BC;LATIN CAPITAL LETTER TONE FIVE;Lu;0;L;;;;;N;;;;01BD; => +1
                    01BD;LATIN SMALL LETTER TONE FIVE;Ll;0;L;;;;;N;;;01BC;;01BC <=
                    01BE;LATIN LETTER INVERTED GLOTTAL STOP WITH STROKE;Ll;0;L;;;;;N;LATIN LETTER INVERTED GLOTTAL STOP BAR;;;; X
                    01BF;LATIN LETTER WYNN;Ll;0;L;;;;;N;;;01F7;;01F7  <=
                    }
                    #$B8,#$BC:
                    begin
                      if ord(c2) mod 2 = 0 then
                        exit(STUpLetter);
                    end;
                    #$B3..#$B6:
                    begin
                      if ord(c2) mod 2 = 1 then
                        exit(STUpLetter);
                    end;
                    #$B1:
                    begin
                      exit(STUpLetter);
                    end;
                    #$B2:
                    begin
                      exit(STUpLetter);
                    end;
                    #$B7:
                    begin
                      exit(STUpLetter);
                    end;
                    end;
                  end;
                  #$C7:
                  begin
                    case c2 of
                    #$84..#$8C,#$B1..#$B3:
                    begin
                      if (ord(c2) and $F) mod 3 = 1 then exit(STUpLetter)
                      else if (ord(c2) and $F) mod 3 = 2 then exit(STUpLetter);
                    end;
                    #$8D..#$9C:
                    begin
                      if ord(c2) mod 2 = 1 then
                        exit(STUpLetter);
                    end;
                    #$9E..#$AF,#$B4..#$B5,#$B8..#$BF:
                    begin
                      if ord(c2) mod 2 = 0 then
                        exit(STUpLetter);
                    end;
                    {
                    01F6;LATIN CAPITAL LETTER HWAIR;Lu;0;L;;;;;N;;;;0195;
                    01F7;LATIN CAPITAL LETTER WYNN;Lu;0;L;;;;;N;;;;01BF;
                    }
                    #$B6:
                    begin
                      exit(STUpLetter);
                    end;
                    #$B7:
                    begin
                      exit(STUpLetter);
                    end;
                    end;
                  end;
                  {
                  Codepoints 0200 to 023F
                  }
                  #$C8:
                  begin
                    // For this one we can simply start with a default and override for some specifics
                    if (c2 in [#$80..#$B3]) and (ord(c2) mod 2 = 0) then exit(STUpLetter);

                    case c2 of
                    #$A0:
                    begin
                      exit(STUpLetter);
                    end;
                    #$A1: exit(STUpLetter);
                    {
                    023A;LATIN CAPITAL LETTER A WITH STROKE;Lu;0;L;;;;;N;;;;2C65; => E2 B1 A5
                    023B;LATIN CAPITAL LETTER C WITH STROKE;Lu;0;L;;;;;N;;;;023C; => +1
                    023C;LATIN SMALL LETTER C WITH STROKE;Ll;0;L;;;;;N;;;023B;;023B <=
                    023D;LATIN CAPITAL LETTER L WITH BAR;Lu;0;L;;;;;N;;;;019A; => C6 9A
                    023E;LATIN CAPITAL LETTER T WITH DIAGONAL STROKE;Lu;0;L;;;;;N;;;;2C66; => E2 B1 A6
                    023F;LATIN SMALL LETTER S WITH SWASH TAIL;Ll;0;L;;;;;N;;;2C7E;;2C7E <=
                    0240;LATIN SMALL LETTER Z WITH SWASH TAIL;Ll;0;L;;;;;N;;;2C7F;;2C7F <=
                    }
                    #$BA,#$BE:
                    begin
                      exit(STUpLetter);
                    end;
                    #$BD:
                    begin
                      exit(STUpLetter);
                    end;
                    #$BB: exit(STUpLetter);
                    end;
                  end;
                  {
                  Codepoints 0240 to 027F

                  Here only 0240..024F needs lowercase
                  }
                  #$C9:
                  begin
                    case c2 of
                    #$81..#$82:
                    begin
                      if ord(c2) mod 2 = 1 then
                        exit(STUpLetter);
                    end;
                    #$86..#$8F:
                    begin
                      if ord(c2) mod 2 = 0 then
                        exit(STUpLetter);
                    end;
                    #$83:
                    begin
                      exit(STUpLetter);
                    end;
                    #$84:
                    begin
                      exit(STUpLetter);
                    end;
                    #$85:
                    begin
                      exit(STUpLetter);
                    end;
                    end;
                  end;
                  // $CE91..$CE9F: NewChar := OldChar + $20; // Greek Characters
                  // $CEA0..$CEA9: NewChar := OldChar + $E0; // Greek Characters
                  #$CE:
                  begin
                    case c2 of
                      // 0380 = CE 80
                      #$86: exit(STUpLetter);
                      #$88: exit(STUpLetter);
                      #$89: exit(STUpLetter);
                      #$8A: exit(STUpLetter);
                      #$8C: exit(STUpLetter); // By coincidence new_c2 remains the same
                      #$8E:
                      begin
                        exit(STUpLetter);
                      end;
                      #$8F:
                      begin
                        exit(STUpLetter);
                      end;
                      // 0390 = CE 90
                      #$91..#$9F:
                      begin
                        exit(STUpLetter);
                      end;
                      // 03A0 = CE A0
                      #$A0..#$AB:
                      begin
                        exit(STUpLetter);
                      end;
                    end;
                  end;
                  // 03C0 = CF 80
                  // 03D0 = CF 90
                  // 03E0 = CF A0
                  // 03F0 = CF B0
                  #$CF:
                  begin
                    case c2 of
                      // 03CF;GREEK CAPITAL KAI SYMBOL;Lu;0;L;;;;;N;;;;03D7; CF 8F => CF 97
                      #$8F: exit(STUpLetter);
                      // 03D8;GREEK LETTER ARCHAIC KOPPA;Lu;0;L;;;;;N;;;;03D9;
                      #$98: exit(STUpLetter);
                      // 03DA;GREEK LETTER STIGMA;Lu;0;L;;;;;N;GREEK CAPITAL LETTER STIGMA;;;03DB;
                      #$9A: exit(STUpLetter);
                      // 03DC;GREEK LETTER DIGAMMA;Lu;0;L;;;;;N;GREEK CAPITAL LETTER DIGAMMA;;;03DD;
                      #$9C: exit(STUpLetter);
                      // 03DE;GREEK LETTER KOPPA;Lu;0;L;;;;;N;GREEK CAPITAL LETTER KOPPA;;;03DF;
                      #$9E: exit(STUpLetter);
                      {
                      03E0;GREEK LETTER SAMPI;Lu;0;L;;;;;N;GREEK CAPITAL LETTER SAMPI;;;03E1;
                      03E1;GREEK SMALL LETTER SAMPI;Ll;0;L;;;;;N;;;03E0;;03E0
                      03E2;COPTIC CAPITAL LETTER SHEI;Lu;0;L;;;;;N;GREEK CAPITAL LETTER SHEI;;;03E3;
                      03E3;COPTIC SMALL LETTER SHEI;Ll;0;L;;;;;N;GREEK SMALL LETTER SHEI;;03E2;;03E2
                      ...
                      03EE;COPTIC CAPITAL LETTER DEI;Lu;0;L;;;;;N;GREEK CAPITAL LETTER DEI;;;03EF;
                      03EF;COPTIC SMALL LETTER DEI;Ll;0;L;;;;;N;GREEK SMALL LETTER DEI;;03EE;;03EE
                      }
                      #$A0..#$AF: if ord(c2) mod 2 = 0 then
                                    exit(STUpLetter);
                      // 03F4;GREEK CAPITAL THETA SYMBOL;Lu;0;L;<compat> 0398;;;;N;;;;03B8;
                      #$B4:
                      begin
                        exit(STUpLetter);
                      end;
                      // 03F7;GREEK CAPITAL LETTER SHO;Lu;0;L;;;;;N;;;;03F8;
                      #$B7: exit(STUpLetter);
                      // 03F9;GREEK CAPITAL LUNATE SIGMA SYMBOL;Lu;0;L;<compat> 03A3;;;;N;;;;03F2;
                      #$B9: exit(STUpLetter);
                      // 03FA;GREEK CAPITAL LETTER SAN;Lu;0;L;;;;;N;;;;03FB;
                      #$BA: exit(STUpLetter);
                      // 03FD;GREEK CAPITAL REVERSED LUNATE SIGMA SYMBOL;Lu;0;L;;;;;N;;;;037B;
                      #$BD:
                      begin
                        exit(STUpLetter);
                      end;
                      // 03FE;GREEK CAPITAL DOTTED LUNATE SIGMA SYMBOL;Lu;0;L;;;;;N;;;;037C;
                      #$BE:
                      begin
                        exit(STUpLetter);
                      end;
                      // 03FF;GREEK CAPITAL REVERSED DOTTED LUNATE SIGMA SYMBOL;Lu;0;L;;;;;N;;;;037D;
                      #$BF:
                      begin
                        exit(STUpLetter);
                      end;
                    end;
                  end;
                  // $D080..$D08F: NewChar := OldChar + $110; // Cyrillic alphabet
                  // $D090..$D09F: NewChar := OldChar + $20; // Cyrillic alphabet
                  // $D0A0..$D0AF: NewChar := OldChar + $E0; // Cyrillic alphabet
                  #$D0:
                  begin
                    c2 := sym[1];
                    case c2 of
                      #$80..#$8F:
                      begin
                        exit(STUpLetter);
                      end;
                      #$90..#$9F:
                      begin
                        exit(STUpLetter);
                      end;
                      #$A0..#$AF:
                      begin
                        exit(STUpLetter);
                      end;
                    end;
                  end;
                  // Archaic and non-slavic cyrillic 460-47F = D1A0-D1BF
                  // These require just adding 1 to get the lowercase
                  #$D1:
                  begin
                    if (c2 in [#$A0..#$BF]) and (ord(c2) mod 2 = 0) then
                      exit(STUpLetter);
                  end;
                  // Archaic and non-slavic cyrillic 480-4BF = D280-D2BF
                  // These mostly require just adding 1 to get the lowercase
                  #$D2:
                  begin
                    case c2 of
                      #$80:
                      begin
                        exit(STUpLetter);
                      end;
                      // #$81 is already lowercase
                      // #$82-#$89 ???
                      #$8A..#$BF:
                      begin
                        if ord(c2) mod 2 = 0 then
                          exit(STUpLetter);
                      end;
                    end;
                  end;
                  {
                  Codepoints  04C0..04FF
                  }
                  #$D3:
                  begin
                    case c2 of
                      #$80: exit(STUpLetter);
                      #$81..#$8E:
                      begin
                        if ord(c2) mod 2 = 1 then
                          exit(STUpLetter);
                      end;
                      #$90..#$BF:
                      begin
                        if ord(c2) mod 2 = 0 then
                          exit(STUpLetter);
                      end;
                    end;
                  end;
                  {
                  Codepoints  0500..053F

                  Armenian starts in 0531
                  }
                  #$D4:
                  begin
                    if ord(c2) mod 2 = 0 then
                      exit(STUpLetter);

                    // Armenian
                    if c2 in [#$B1..#$BF] then
                    begin
                      exit(STUpLetter);
                    end;
                  end;
                  {
                  Codepoints  0540..057F

                  Armenian
                  }
                  #$D5:
                  begin
                    case c2 of
                      #$80..#$8F:
                      begin
                        exit(STUpLetter);
                      end;
                      #$90..#$96:
                      begin
                        exit(STUpLetter);
                      end;
                    end;
                  end;


                  {
                  characters with 3 bytes
                  }
                    #$E1:
                    begin
                      c2 := sym[1];
                      c3 := sym[2];
                      {
                      Georgian codepoints 10A0-10C5 => 2D00-2D25

                      In UTF-8 this is:
                      E1 82 A0 - E1 82 BF => E2 B4 80 - E2 B4 9F
                      E1 83 80 - E1 83 85 => E2 B4 A0 - E2 B4 A5
                      }
                      case c2 of
                      #$82:
                      if (c3 in [#$A0..#$BF]) then
                      begin
                        exit(STUpLetter);
                      end;
                      #$83:
                      if (c3 in [#$80..#$85]) then
                      begin
                        exit(STUpLetter);
                      end;
                      {
                      Extra chars between 1E00..1EFF

                      Blocks of chars:
                        1E00..1E3F    E1 B8 80..E1 B8 BF
                        1E40..1E7F    E1 B9 80..E1 B9 BF
                        1E80..1EBF    E1 BA 80..E1 BA BF
                        1EC0..1EFF    E1 BB 80..E1 BB BF
                      }
                      #$B8..#$BB:
                      begin
                        exit(STUpLetter)
                      end;
                      {
                      Extra chars between 1F00..1FFF

                      Blocks of chars:
                        1E00..1E3F    E1 BC 80..E1 BC BF
                        1E40..1E7F    E1 BD 80..E1 BD BF
                        1E80..1EBF    E1 BE 80..E1 BE BF
                        1EC0..1EFF    E1 BF 80..E1 BF BF
                      }
                      #$BC:
                      begin
                        // Start with a default and change for some particular chars
                        if (ord(c3) mod $10) div 8 = 1 then
                          exit(STUpLetter);
                      end;
                      #$BD:
                      begin
                        // Start with a default and change for some particular chars
                        case c3 of
                        #$80..#$8F, #$A0..#$AF: if (ord(c3) mod $10) div 8 = 1 then
                                      exit(STUpLetter);
                        {
                        1F50;GREEK SMALL LETTER UPSILON WITH PSILI;Ll;0;L;03C5 0313;;;;N;;;;;
                        1F51;GREEK SMALL LETTER UPSILON WITH DASIA;Ll;0;L;03C5 0314;;;;N;;;1F59;;1F59
                        1F52;GREEK SMALL LETTER UPSILON WITH PSILI AND VARIA;Ll;0;L;1F50 0300;;;;N;;;;;
                        1F53;GREEK SMALL LETTER UPSILON WITH DASIA AND VARIA;Ll;0;L;1F51 0300;;;;N;;;1F5B;;1F5B
                        1F54;GREEK SMALL LETTER UPSILON WITH PSILI AND OXIA;Ll;0;L;1F50 0301;;;;N;;;;;
                        1F55;GREEK SMALL LETTER UPSILON WITH DASIA AND OXIA;Ll;0;L;1F51 0301;;;;N;;;1F5D;;1F5D
                        1F56;GREEK SMALL LETTER UPSILON WITH PSILI AND PERISPOMENI;Ll;0;L;1F50 0342;;;;N;;;;;
                        1F57;GREEK SMALL LETTER UPSILON WITH DASIA AND PERISPOMENI;Ll;0;L;1F51 0342;;;;N;;;1F5F;;1F5F
                        1F59;GREEK CAPITAL LETTER UPSILON WITH DASIA;Lu;0;L;03A5 0314;;;;N;;;;1F51;
                        1F5B;GREEK CAPITAL LETTER UPSILON WITH DASIA AND VARIA;Lu;0;L;1F59 0300;;;;N;;;;1F53;
                        1F5D;GREEK CAPITAL LETTER UPSILON WITH DASIA AND OXIA;Lu;0;L;1F59 0301;;;;N;;;;1F55;
                        1F5F;GREEK CAPITAL LETTER UPSILON WITH DASIA AND PERISPOMENI;Lu;0;L;1F59 0342;;;;N;;;;1F57;
                        }
                        #$99,#$9B,#$9D,#$9F: exit(STUpLetter);
                        end;
                      end;
                      #$BE:
                      begin
                        // Start with a default and change for some particular chars
                        case c3 of
                        #$80..#$B9: if (ord(c3) mod $10) div 8 = 1 then
                                      exit(STUpLetter);
                        {
                        1FB0;GREEK SMALL LETTER ALPHA WITH VRACHY;Ll;0;L;03B1 0306;;;;N;;;1FB8;;1FB8
                        1FB1;GREEK SMALL LETTER ALPHA WITH MACRON;Ll;0;L;03B1 0304;;;;N;;;1FB9;;1FB9
                        1FB2;GREEK SMALL LETTER ALPHA WITH VARIA AND YPOGEGRAMMENI;Ll;0;L;1F70 0345;;;;N;;;;;
                        1FB3;GREEK SMALL LETTER ALPHA WITH YPOGEGRAMMENI;Ll;0;L;03B1 0345;;;;N;;;1FBC;;1FBC
                        1FB4;GREEK SMALL LETTER ALPHA WITH OXIA AND YPOGEGRAMMENI;Ll;0;L;03AC 0345;;;;N;;;;;
                        1FB6;GREEK SMALL LETTER ALPHA WITH PERISPOMENI;Ll;0;L;03B1 0342;;;;N;;;;;
                        1FB7;GREEK SMALL LETTER ALPHA WITH PERISPOMENI AND YPOGEGRAMMENI;Ll;0;L;1FB6 0345;;;;N;;;;;
                        1FB8;GREEK CAPITAL LETTER ALPHA WITH VRACHY;Lu;0;L;0391 0306;;;;N;;;;1FB0;
                        1FB9;GREEK CAPITAL LETTER ALPHA WITH MACRON;Lu;0;L;0391 0304;;;;N;;;;1FB1;
                        1FBA;GREEK CAPITAL LETTER ALPHA WITH VARIA;Lu;0;L;0391 0300;;;;N;;;;1F70;
                        1FBB;GREEK CAPITAL LETTER ALPHA WITH OXIA;Lu;0;L;0386;;;;N;;;;1F71;
                        1FBC;GREEK CAPITAL LETTER ALPHA WITH PROSGEGRAMMENI;Lt;0;L;0391 0345;;;;N;;;;1FB3;
                        1FBD;GREEK KORONIS;Sk;0;ON;<compat> 0020 0313;;;;N;;;;;
                        1FBE;GREEK PROSGEGRAMMENI;Ll;0;L;03B9;;;;N;;;0399;;0399
                        1FBF;GREEK PSILI;Sk;0;ON;<compat> 0020 0313;;;;N;;;;;
                        }
                        #$BA:
                        begin
                          exit(STUpLetter);
                        end;
                        #$BB:
                        begin
                          exit(STUpLetter);
                        end;
                        #$BC: exit(STUpLetter);
                        end;
                      end;
                      end;
                    end;
                    {
                    More Characters with 3 bytes, so exotic stuff between:
                    $2126..$2183                    E2 84 A6..E2 86 83
                    $24B6..$24CF    Result:=u+26;   E2 92 B6..E2 93 8F
                    $2C00..$2C2E    Result:=u+48;   E2 B0 80..E2 B0 AE
                    $2C60..$2CE2                    E2 B1 A0..E2 B3 A2
                    }
                    #$E2:
                    begin
                      c2 := sym[1];
                      c3 := sym[2];
                      // 2126;OHM SIGN;Lu;0;L;03A9;;;;N;OHM;;;03C9; E2 84 A6 => CF 89
                      if (c2 = #$84) and (c3 = #$A6) then
                      begin
                        exit(STUpLetter);
                      end
                      {
                      212A;KELVIN SIGN;Lu;0;L;004B;;;;N;DEGREES KELVIN;;;006B; E2 84 AA => 6B
                      }
                      else if (c2 = #$84) and (c3 = #$AA) then
                      begin
                        exit(STUpLetter);
                      end
                      {
                      212B;ANGSTROM SIGN;Lu;0;L;00C5;;;;N;ANGSTROM UNIT;;;00E5; E2 84 AB => C3 A5
                      }
                      else if (c2 = #$84) and (c3 = #$AB) then
                      begin
                        exit(STUpLetter);
                      end
                      {
                      2160;ROMAN NUMERAL ONE;Nl;0;L;<compat> 0049;;;1;N;;;;2170; E2 85 A0 => E2 85 B0
                      2161;ROMAN NUMERAL TWO;Nl;0;L;<compat> 0049 0049;;;2;N;;;;2171;
                      2162;ROMAN NUMERAL THREE;Nl;0;L;<compat> 0049 0049 0049;;;3;N;;;;2172;
                      2163;ROMAN NUMERAL FOUR;Nl;0;L;<compat> 0049 0056;;;4;N;;;;2173;
                      2164;ROMAN NUMERAL FIVE;Nl;0;L;<compat> 0056;;;5;N;;;;2174;
                      2165;ROMAN NUMERAL SIX;Nl;0;L;<compat> 0056 0049;;;6;N;;;;2175;
                      2166;ROMAN NUMERAL SEVEN;Nl;0;L;<compat> 0056 0049 0049;;;7;N;;;;2176;
                      2167;ROMAN NUMERAL EIGHT;Nl;0;L;<compat> 0056 0049 0049 0049;;;8;N;;;;2177;
                      2168;ROMAN NUMERAL NINE;Nl;0;L;<compat> 0049 0058;;;9;N;;;;2178;
                      2169;ROMAN NUMERAL TEN;Nl;0;L;<compat> 0058;;;10;N;;;;2179;
                      216A;ROMAN NUMERAL ELEVEN;Nl;0;L;<compat> 0058 0049;;;11;N;;;;217A;
                      216B;ROMAN NUMERAL TWELVE;Nl;0;L;<compat> 0058 0049 0049;;;12;N;;;;217B;
                      216C;ROMAN NUMERAL FIFTY;Nl;0;L;<compat> 004C;;;50;N;;;;217C;
                      216D;ROMAN NUMERAL ONE HUNDRED;Nl;0;L;<compat> 0043;;;100;N;;;;217D;
                      216E;ROMAN NUMERAL FIVE HUNDRED;Nl;0;L;<compat> 0044;;;500;N;;;;217E;
                      216F;ROMAN NUMERAL ONE THOUSAND;Nl;0;L;<compat> 004D;;;1000;N;;;;217F;
                      }
                      else if (c2 = #$85) and (c3 in [#$A0..#$AF]) then exit(STUpLetter)
                      {
                      2183;ROMAN NUMERAL REVERSED ONE HUNDRED;Lu;0;L;;;;;N;;;;2184; E2 86 83 => E2 86 84
                      }
                      else if (c2 = #$86) and (c3 = #$83) then exit(STUpLetter)
                      {
                      $24B6..$24CF    Result:=u+26;   E2 92 B6..E2 93 8F

                      Ex: 24B6;CIRCLED LATIN CAPITAL LETTER A;So;0;L;<circle> 0041;;;;N;;;;24D0; E2 92 B6 => E2 93 90
                      }
                      else if (c2 = #$92) and (c3 in [#$B6..#$BF]) then
                      begin
                        exit(STUpLetter);
                      end
                      // CIRCLED LATIN CAPITAL LETTER K  $24C0 -> $24DA
                      else if (c2 = #$93) and (c3 in [#$80..#$8F]) then exit(STUpLetter)
                      {
                      $2C00..$2C2E    Result:=u+48;   E2 B0 80..E2 B0 AE

                      2C00;GLAGOLITIC CAPITAL LETTER AZU;Lu;0;L;;;;;N;;;;2C30; E2 B0 80 => E2 B0 B0

                      2C10;GLAGOLITIC CAPITAL LETTER NASHI;Lu;0;L;;;;;N;;;;2C40; E2 B0 90 => E2 B1 80
                      }
                      else if (c2 = #$B0) and (c3 in [#$80..#$8F]) then exit(STUpLetter)
                      else if (c2 = #$B0) and (c3 in [#$90..#$AE]) then
                      begin
                        exit(STUpLetter);
                      end
                      {
                      $2C60..$2CE2                    E2 B1 A0..E2 B3 A2

                      2C60;LATIN CAPITAL LETTER L WITH DOUBLE BAR;Lu;0;L;;;;;N;;;;2C61; E2 B1 A0 => +1
                      2C61;LATIN SMALL LETTER L WITH DOUBLE BAR;Ll;0;L;;;;;N;;;2C60;;2C60
                      2C62;LATIN CAPITAL LETTER L WITH MIDDLE TILDE;Lu;0;L;;;;;N;;;;026B; => 	C9 AB
                      2C63;LATIN CAPITAL LETTER P WITH STROKE;Lu;0;L;;;;;N;;;;1D7D; => E1 B5 BD
                      2C64;LATIN CAPITAL LETTER R WITH TAIL;Lu;0;L;;;;;N;;;;027D; => 	C9 BD
                      2C65;LATIN SMALL LETTER A WITH STROKE;Ll;0;L;;;;;N;;;023A;;023A
                      2C66;LATIN SMALL LETTER T WITH DIAGONAL STROKE;Ll;0;L;;;;;N;;;023E;;023E
                      2C67;LATIN CAPITAL LETTER H WITH DESCENDER;Lu;0;L;;;;;N;;;;2C68; => E2 B1 A8
                      2C68;LATIN SMALL LETTER H WITH DESCENDER;Ll;0;L;;;;;N;;;2C67;;2C67
                      2C69;LATIN CAPITAL LETTER K WITH DESCENDER;Lu;0;L;;;;;N;;;;2C6A; => E2 B1 AA
                      2C6A;LATIN SMALL LETTER K WITH DESCENDER;Ll;0;L;;;;;N;;;2C69;;2C69
                      2C6B;LATIN CAPITAL LETTER Z WITH DESCENDER;Lu;0;L;;;;;N;;;;2C6C; => E2 B1 AC
                      2C6C;LATIN SMALL LETTER Z WITH DESCENDER;Ll;0;L;;;;;N;;;2C6B;;2C6B
                      2C6D;LATIN CAPITAL LETTER ALPHA;Lu;0;L;;;;;N;;;;0251; => C9 91
                      2C6E;LATIN CAPITAL LETTER M WITH HOOK;Lu;0;L;;;;;N;;;;0271; => C9 B1
                      2C6F;LATIN CAPITAL LETTER TURNED A;Lu;0;L;;;;;N;;;;0250; => C9 90

                      2C70;LATIN CAPITAL LETTER TURNED ALPHA;Lu;0;L;;;;;N;;;;0252; => C9 92
                      }
                      else if (c2 = #$B1) then
                      begin
                        case c3 of
                        #$A0: exit(STUpLetter);
                        #$A2,#$A4,#$AD..#$AF,#$B0:
                        begin
                          exit(STUpLetter);
                        end;
                        #$A3:
                        begin
                          exit(STUpLetter);
                        end;
                        #$A7,#$A9,#$AB: exit(STUpLetter);
                        {
                        2C71;LATIN SMALL LETTER V WITH RIGHT HOOK;Ll;0;L;;;;;N;;;;;
                        2C72;LATIN CAPITAL LETTER W WITH HOOK;Lu;0;L;;;;;N;;;;2C73;
                        2C73;LATIN SMALL LETTER W WITH HOOK;Ll;0;L;;;;;N;;;2C72;;2C72
                        2C74;LATIN SMALL LETTER V WITH CURL;Ll;0;L;;;;;N;;;;;
                        2C75;LATIN CAPITAL LETTER HALF H;Lu;0;L;;;;;N;;;;2C76;
                        2C76;LATIN SMALL LETTER HALF H;Ll;0;L;;;;;N;;;2C75;;2C75
                        2C77;LATIN SMALL LETTER TAILLESS PHI;Ll;0;L;;;;;N;;;;;
                        2C78;LATIN SMALL LETTER E WITH NOTCH;Ll;0;L;;;;;N;;;;;
                        2C79;LATIN SMALL LETTER TURNED R WITH TAIL;Ll;0;L;;;;;N;;;;;
                        2C7A;LATIN SMALL LETTER O WITH LOW RING INSIDE;Ll;0;L;;;;;N;;;;;
                        2C7B;LATIN LETTER SMALL CAPITAL TURNED E;Ll;0;L;;;;;N;;;;;
                        2C7C;LATIN SUBSCRIPT SMALL LETTER J;Ll;0;L;<sub> 006A;;;;N;;;;;
                        2C7D;MODIFIER LETTER CAPITAL V;Lm;0;L;<super> 0056;;;;N;;;;;
                        2C7E;LATIN CAPITAL LETTER S WITH SWASH TAIL;Lu;0;L;;;;;N;;;;023F; => C8 BF
                        2C7F;LATIN CAPITAL LETTER Z WITH SWASH TAIL;Lu;0;L;;;;;N;;;;0240; => C9 80
                        }
                        #$B2,#$B5: exit(STUpLetter);
                        #$BE,#$BF:
                        begin
                          exit(STUpLetter);
                        end;
                        end;
                      end
                      {
                      2C80;COPTIC CAPITAL LETTER ALFA;Lu;0;L;;;;;N;;;;2C81; E2 B2 80 => E2 B2 81
                      ...
                      2CBE;COPTIC CAPITAL LETTER OLD COPTIC OOU;Lu;0;L;;;;;N;;;;2CBF; E2 B2 BE => E2 B2 BF
                      2CBF;COPTIC SMALL LETTER OLD COPTIC OOU;Ll;0;L;;;;;N;;;2CBE;;2CBE
                      ...
                      2CC0;COPTIC CAPITAL LETTER SAMPI;Lu;0;L;;;;;N;;;;2CC1; E2 B3 80 => E2 B2 81
                      2CC1;COPTIC SMALL LETTER SAMPI;Ll;0;L;;;;;N;;;2CC0;;2CC0
                      ...
                      2CE2;COPTIC CAPITAL LETTER OLD NUBIAN WAU;Lu;0;L;;;;;N;;;;2CE3; E2 B3 A2 => E2 B3 A3
                      2CE3;COPTIC SMALL LETTER OLD NUBIAN WAU;Ll;0;L;;;;;N;;;2CE2;;2CE2 <=
                      }
                      else if (c2 = #$B2) then
                      begin
                        if ord(c3) mod 2 = 0 then exit(STUpLetter);
                      end
                      else if (c2 = #$B3) and (c3 in [#$80..#$A3]) then
                      begin
                        if ord(c3) mod 2 = 0 then exit(STUpLetter);
                      end;
                    end;
                    {
                    FF21;FULLWIDTH LATIN CAPITAL LETTER A;Lu;0;L;<wide> 0041;;;;N;;;;FF41; EF BC A1 => EF BD 81
                    ...
                    FF3A;FULLWIDTH LATIN CAPITAL LETTER Z;Lu;0;L;<wide> 005A;;;;N;;;;FF5A; EF BC BA => EF BD 9A
                    }
                    #$EF:
                    begin
                      c2 := sym[1];
                      c3 := sym[2];

                      if (c2 = #$BC) and (c3 in [#$A1..#$BA]) then
                      begin
                        exit(STUpLetter);
                      end;
                    end;
                  end;
                end;
              end;
              //from UTF8Uppercase
              OldChar := (Ord(sym[0]) shl 8) or Ord(sym[1]);
              case OldChar of
                // Latin Characters 0000–0FFF http://en.wikibooks.org/wiki/Unicode/Character_reference/0000-0FFF
                $C39F:exit(STLowLetter); // ß => SS
                $C3A0..$C3B6,$C3B8..$C3BE:exit(STLowLetter);
                $C3BF:exit(STLowLetter); // ÿ
                $C481..$C4B0: if OldChar mod 2 = 1 then exit(STLowLetter);
                // 0130 = C4 B0
                // turkish small undotted i to capital undotted i
                $C4B1:exit(STLowLetter);
                $C4B2..$C4B7: if OldChar mod 2 = 1 then exit(STLowLetter);
                // $C4B8: ĸ without upper/lower
                $C4B9..$C4BF: if OldChar mod 2 = 0 then exit(STLowLetter);
                $C580: exit(STLowLetter); // border between bytes
                $C581..$C588: if OldChar mod 2 = 0 then exit(STLowLetter);
                // $C589 ŉ => ?
                $C58A..$C5B7: if OldChar mod 2 = 1 then exit(STLowLetter);
                // $C5B8: // Ÿ already uppercase
                $C5B9..$C5BE: if OldChar mod 2 = 0 then exit(STLowLetter);
                $C5BF: // 017F
                  exit(STLowLetter);
                // 0180 = C6 80 -> A convoluted part
                $C680: exit(STLowLetter);
                $C682..$C685: if OldChar mod 2 = 1 then exit(STLowLetter);
                $C688: exit(STLowLetter);
                $C68C: exit(STLowLetter);
                // 0190 = C6 90 -> A convoluted part
                $C692: exit(STLowLetter);
                $C695: exit(STLowLetter);
                $C699: exit(STLowLetter);
                $C69A: exit(STLowLetter);
                $C69E: exit(STLowLetter);
                // 01A0 = C6 A0 -> A convoluted part
                $C6A0..$C6A5: if OldChar mod 2 = 1 then exit(STLowLetter);
                $C6A8: exit(STLowLetter);
                $C6AD: exit(STLowLetter);
                // 01B0 = C6 B0
                $C6B0: exit(STLowLetter);
                $C6B3..$C6B6: if OldChar mod 2 = 0 then exit(STLowLetter);
                $C6B9: exit(STLowLetter);
                $C6BD: exit(STLowLetter);
                $C6BF: exit(STLowLetter);
                // 01C0 = C7 80
                $C784..$C786: exit(STLowLetter);
                $C787..$C789: exit(STLowLetter);
                $C78A..$C78C: exit(STLowLetter);
                $C78E: exit(STLowLetter);
                // 01D0 = C7 90
                $C790: exit(STLowLetter);
                $C791..$C79C: if OldChar mod 2 = 0 then exit(STLowLetter);
                $C79D: exit(STLowLetter);
                $C79F: exit(STLowLetter);
                // 01E0 = C7 A0
                $C7A0..$C7AF: if OldChar mod 2 = 1 then exit(STLowLetter);
                // 01F0 = C7 B0
                $C7B2..$C7B3: exit(STLowLetter);
                $C7B5: exit(STLowLetter);
                $C7B8..$C7BF: if OldChar mod 2 = 1 then exit(STLowLetter);
                // 0200 = C8 80
                // 0210 = C8 90
                $C880..$C89F: if OldChar mod 2 = 1 then exit(STLowLetter);
                // 0220 = C8 A0
                // 0230 = C8 B0
                $C8A2..$C8B3: if OldChar mod 2 = 1 then exit(STLowLetter);
                $C8BC: exit(STLowLetter);
                $C8BF: exit(STLowLetter);
                // 0240 = C9 80
                $C980: exit(STLowLetter);
                $C982: exit(STLowLetter);
                $C986..$C98F: if OldChar mod 2 = 1 then exit(STLowLetter);
                // 0250 = C9 90
                $C990: exit(STLowLetter);
                $C991: exit(STLowLetter);
                $C992: exit(STLowLetter);
                $C993: exit(STLowLetter);
                $C994: exit(STLowLetter);
                $C996: exit(STLowLetter);
                $C997: exit(STLowLetter);
                $C999: exit(STLowLetter);
                $C99B: exit(STLowLetter);
                // 0260 = C9 A0
                $C9A0: exit(STLowLetter);
                $C9A3: exit(STLowLetter);
                $C9A5: exit(STLowLetter);
                $C9A8: exit(STLowLetter);
                $C9A9: exit(STLowLetter);
                $C9AB: exit(STLowLetter);
                $C9AF: exit(STLowLetter);
                // 0270 = C9 B0
                $C9B1: exit(STLowLetter);
                $C9B2: exit(STLowLetter);
                $C9B5: exit(STLowLetter);
                $C9BD: exit(STLowLetter);
                // 0280 = CA 80
                $CA80: exit(STLowLetter);
                $CA83: exit(STLowLetter);
                $CA88: exit(STLowLetter);
                $CA89: exit(STLowLetter);
                $CA8A: exit(STLowLetter);
                $CA8B: exit(STLowLetter);
                $CA8C: exit(STLowLetter);
                // 0290 = CA 90
                $CA92: exit(STLowLetter);
                {
                03A0 = CE A0

                03AC;GREEK SMALL LETTER ALPHA WITH TONOS;Ll;0;L;03B1 0301;;;;N;GREEK SMALL LETTER ALPHA TONOS;;0386;;0386
                03AD;GREEK SMALL LETTER EPSILON WITH TONOS;Ll;0;L;03B5 0301;;;;N;GREEK SMALL LETTER EPSILON TONOS;;0388;;0388
                03AE;GREEK SMALL LETTER ETA WITH TONOS;Ll;0;L;03B7 0301;;;;N;GREEK SMALL LETTER ETA TONOS;;0389;;0389
                03AF;GREEK SMALL LETTER IOTA WITH TONOS;Ll;0;L;03B9 0301;;;;N;GREEK SMALL LETTER IOTA TONOS;;038A;;038A
                }
                $CEAC: exit(STLowLetter);
                $CEAD: exit(STLowLetter);
                $CEAE: exit(STLowLetter);
                $CEAF: exit(STLowLetter);
                {
                03B0 = CE B0

                03B0;GREEK SMALL LETTER UPSILON WITH DIALYTIKA AND TONOS;Ll;0;L;03CB 0301;;;;N;GREEK SMALL LETTER UPSILON DIAERESIS TONOS;;;;
                03B1;GREEK SMALL LETTER ALPHA;Ll;0;L;;;;;N;;;0391;;0391
                ...
                03BF;GREEK SMALL LETTER OMICRON;Ll;0;L;;;;;N;;;039F;;039F
                }
                $CEB1..$CEBF: exit(STLowLetter); // Greek Characters
                {
                03C0 = CF 80

                03C0;GREEK SMALL LETTER PI;Ll;0;L;;;;;N;;;03A0;;03A0 CF 80 => CE A0
                03C1;GREEK SMALL LETTER RHO;Ll;0;L;;;;;N;;;03A1;;03A1
                03C2;GREEK SMALL LETTER FINAL SIGMA;Ll;0;L;;;;;N;;;03A3;;03A3
                03C3;GREEK SMALL LETTER SIGMA;Ll;0;L;;;;;N;;;03A3;;03A3
                03C4;GREEK SMALL LETTER TAU;Ll;0;L;;;;;N;;;03A4;;03A4
                ....
                03CB;GREEK SMALL LETTER UPSILON WITH DIALYTIKA;Ll;0;L;03C5 0308;;;;N;GREEK SMALL LETTER UPSILON DIAERESIS;;03AB;;03AB
                03CC;GREEK SMALL LETTER OMICRON WITH TONOS;Ll;0;L;03BF 0301;;;;N;GREEK SMALL LETTER OMICRON TONOS;;038C;;038C
                03CD;GREEK SMALL LETTER UPSILON WITH TONOS;Ll;0;L;03C5 0301;;;;N;GREEK SMALL LETTER UPSILON TONOS;;038E;;038E
                03CE;GREEK SMALL LETTER OMEGA WITH TONOS;Ll;0;L;03C9 0301;;;;N;GREEK SMALL LETTER OMEGA TONOS;;038F;;038F
                03CF;GREEK CAPITAL KAI SYMBOL;Lu;0;L;;;;;N;;;;03D7;
                }
                $CF80,$CF81,$CF83..$CF8B: exit(STLowLetter); // Greek Characters
                $CF82: exit(STLowLetter);
                $CF8C: exit(STLowLetter);
                $CF8D: exit(STLowLetter);
                $CF8E: exit(STLowLetter);
                {
                03D0 = CF 90

                03D0;GREEK BETA SYMBOL;Ll;0;L;<compat> 03B2;;;;N;GREEK SMALL LETTER CURLED BETA;;0392;;0392 CF 90 => CE 92
                03D1;GREEK THETA SYMBOL;Ll;0;L;<compat> 03B8;;;;N;GREEK SMALL LETTER SCRIPT THETA;;0398;;0398 => CE 98
                03D5;GREEK PHI SYMBOL;Ll;0;L;<compat> 03C6;;;;N;GREEK SMALL LETTER SCRIPT PHI;;03A6;;03A6 => CE A6
                03D6;GREEK PI SYMBOL;Ll;0;L;<compat> 03C0;;;;N;GREEK SMALL LETTER OMEGA PI;;03A0;;03A0 => CE A0
                03D7;GREEK KAI SYMBOL;Ll;0;L;;;;;N;;;03CF;;03CF => CF 8F
                03D9;GREEK SMALL LETTER ARCHAIC KOPPA;Ll;0;L;;;;;N;;;03D8;;03D8
                03DB;GREEK SMALL LETTER STIGMA;Ll;0;L;;;;;N;;;03DA;;03DA
                03DD;GREEK SMALL LETTER DIGAMMA;Ll;0;L;;;;;N;;;03DC;;03DC
                03DF;GREEK SMALL LETTER KOPPA;Ll;0;L;;;;;N;;;03DE;;03DE
                }
                $CF90: exit(STLowLetter);
                $CF91: exit(STLowLetter);
                $CF95: exit(STLowLetter);
                $CF96: exit(STLowLetter);
                $CF97: exit(STLowLetter);
                $CF99..$CF9F: if OldChar mod 2 = 1 then exit(STLowLetter);
                // 03E0 = CF A0
                $CFA0..$CFAF: if OldChar mod 2 = 1 then exit(STLowLetter);
                {
                03F0 = CF B0

                03F0;GREEK KAPPA SYMBOL;Ll;0;L;<compat> 03BA;;;;N;GREEK SMALL LETTER SCRIPT KAPPA;;039A;;039A => CE 9A
                03F1;GREEK RHO SYMBOL;Ll;0;L;<compat> 03C1;;;;N;GREEK SMALL LETTER TAILED RHO;;03A1;;03A1 => CE A1
                03F2;GREEK LUNATE SIGMA SYMBOL;Ll;0;L;<compat> 03C2;;;;N;GREEK SMALL LETTER LUNATE SIGMA;;03F9;;03F9
                03F5;GREEK LUNATE EPSILON SYMBOL;Ll;0;L;<compat> 03B5;;;;N;;;0395;;0395 => CE 95
                03F8;GREEK SMALL LETTER SHO;Ll;0;L;;;;;N;;;03F7;;03F7
                03FB;GREEK SMALL LETTER SAN;Ll;0;L;;;;;N;;;03FA;;03FA
                }
                $CFB0: exit(STLowLetter);
                $CFB1: exit(STLowLetter);
                $CFB2: exit(STLowLetter);
                $CFB5: exit(STLowLetter);
                $CFB8: exit(STLowLetter);
                $CFBB: exit(STLowLetter);
                // 0400 = D0 80 ... 042F everything already uppercase
                // 0430 = D0 B0
                $D0B0..$D0BF: exit(STLowLetter); // Cyrillic alphabet
                // 0440 = D1 80
                $D180..$D18F: exit(STLowLetter); // Cyrillic alphabet
                // 0450 = D1 90
                $D190..$D19F: exit(STLowLetter); // Cyrillic alphabet
              end;
              exit(STNotLetter);
            end;
          end;
          // already lower, or otherwise not affected
          exit(STLowLetter);
        end;
      end;
      exit(STNotLetter);
    end;
    else
      exit(STNotLetter);
  end;
end;

constructor TSpeller.CreateRec(ALogProc:TLogProc);
begin
  LogProc:=ALogProc;
  Spellers:=TSpellers.Create;
end;

procedure TSpeller.DestroyRec;
begin
  Spellers.Destroy;
end;

function TSpeller.LoadDictionary(const DictName:string;const Lang:string=''):integer;
var
  PSD:TSpellers.PT;
begin
  if FileExists(DictName) then begin
    Result:=Spellers.Size;
    Spellers.Resize(Spellers.Size+1);
    PSD:=Spellers.Mutable[Spellers.Size-1];
    PSD^.Speller.CreateRec('',LogProc);
    if not PSD^.Speller.SetDictionary(DictName) then begin
      PSD^.Speller.DestroyRec;
      Spellers.PopBack;
      //Spellers.Erase(Spellers.Size-1);
      Result:=WrongLang;
    end;
    if Lang<>'' then
      PSD^.Lang:=Lang
    else
      PSD^.Lang:=ChangeFileExt(ExtractFileName(DictName),'');
  end else
    Result:=WrongLang;
end;

function GetPart(out APart:String;var AStr:String;const ASeparator:String):String;
var
  i:Integer;
begin
  i:=pos(ASeparator,AStr);
  if i<>0 then begin
    APart:=copy(AStr,1,i-1);
    AStr:=copy(AStr,i+1,length(AStr)-i);
  end else begin
    APart:=AStr;
    AStr:='';
  end;
  result:=APart;
end;


procedure TSpeller.LoadDictionaries(Dicts:string);
var
  LangDicts,Lang,LangDict:string;
  LangHandle:TLangHandle;
begin
  repeat
    GetPart(LangDicts,Dicts,'|');
    GetPart(Lang,LangDicts,'=');
    if LangDicts='' then begin
      LangDicts:=Lang;
      Lang:=''
    end;
    GetPart(LangDict,LangDicts,';');
    LangHandle:=LoadDictionary(LangDict,Lang);
    while LangDicts<>'' do begin
      GetPart(LangDict,LangDicts,';');
      Spellers.Mutable[LangHandle]^.Speller.AddDictionary(LangDict);
    end;
  until Dicts='';
end;

function TSpeller.SpellWord(Word:String;const CanBeAbbrv:boolean=false):TLangHandle;
var
  i:integer;
  PSD:TSpellers.PT;
begin
  for i:=0 to Spellers.Size-1 do begin
    PSD:=Spellers.Mutable[i];
    if(PSD^.Lang<>CAbbrvDictName)or(CanBeAbbrv)then;
      if PSD^.Speller.Spell(Word) then
        exit(i);
  end;
  Result:=WrongLang;
end;

function TSpeller.SpellTextSimple(Text:String;out ErrW:string;Opt:TSpellOpts):TLangHandle;
var
  startw,endw,characterlen,wordlen:integer;
  word:string;
  t:TLangHandle;
  NeedSpellThisWord,CanBeAbbrv:boolean;
  List:TStringList;
  SugestCount:integer;


  function ItBreackSumbol(i:integer):boolean;
  begin
    if ord(text[i])in[ord('a')..ord('z'),ord('A')..ord('Z')] then begin
      characterlen:=1;
      exit(false);
    end;
    characterlen:=Utf8CodePointLen(@Text[i],4,false);
    if characterlen=1 then
      result:=true
    else
      result:=false;
  end;

  procedure GetWord;
  begin
    CanBeAbbrv:=false;
    while startw<=length(text) do begin
     if not ItBreackSumbol(startw) then
       break;
     inc(startw,characterlen);
    end;
    if startw>length(text) then begin
      endw:=startw;
      NeedSpellThisWord:=false;
      wordlen:=0;
      exit;
    end;
    case GetUtf8SymType(text[startw..startw+characterlen-1]) of
      STLowLetter:begin NeedSpellThisWord:=True;end;
      STUpLetter:begin NeedSpellThisWord:=True;end;
      STNotLetter:NeedSpellThisWord:=false;
    end;
    endw:=startw+characterlen;
    wordlen:=1;
    while endw<=length(text) do begin
      if ItBreackSumbol(endw) then begin
        if characterlen=1 then
          if text[endw]='.' then
            CanBeAbbrv:=true;
        break;
      end;
      if NeedSpellThisWord then
        case GetUtf8SymType(text[endw..endw+characterlen-1]) of
          STLowLetter:;
          STUpLetter:NeedSpellThisWord:=false;
          STNotLetter:NeedSpellThisWord:=false;
        end;
      inc(endw,characterlen);
      inc(wordlen);
    end;

  end;

begin
  ErrW:='';
  result:=NoText;
  if text='' then exit;
  SugestCount:=0;
  list:=nil;
  try
    startw:=1;
    GetWord;
    word:=Copy(text,startw,endw-startw);
    if word<>''then begin
      if (NeedSpellThisWord)and((wordlen>1)or(SOCheckOneLetterWords in opt)) then
        result:=SpellWord(word,CanBeAbbrv);
      if result=WrongLang then begin
        ErrW:=word;
        exit;
      end;
      startw:=endw;
      while startw<=length(text) do begin
        GetWord;
        word:=Copy(text,startw,endw-startw);
        if (NeedSpellThisWord)and((wordlen>1)or(SOCheckOneLetterWords in opt)) and (word<>'') then begin
          t:=SpellWord(word,CanBeAbbrv);
          case t of
            WrongLang:begin
              if ErrW='' then
                ErrW:=ErrW+word
              else
                ErrW:=ErrW+'; '+word;
              if SOFirstError in opt then
                exit(WrongLang);
              if (SOSuggest in opt)and(SugestCount<1) then begin
                if list=nil then begin
                  list:=TStringList.Create;
                  list.LineBreak:=',';
                  list.SkipLastLineBreak:=true;
                end else
                  list.Clear;
                Suggest(word,list);
                if list.Count>0 then begin
                  ErrW:=ErrW+'['+list.Text+']';
                  inc(SugestCount);
                end;
              end;
            end
            else
              if t<>result then
                if result=NoText then
                  result:=t
                else if t<>NoText then
                  result:=MixedLang;
          end;
        end;
        startw:=endw;
      end;
    end;
  finally
    list.Free;
  end;
end;

procedure TSpeller.Suggest(Word:string; List: TStrings);
var
  i:integer;
  PSD:TSpellers.PT;
begin
  for i:=0 to Spellers.Size-1 do begin
    PSD:=Spellers.Mutable[i];
    PSD^.Speller.Suggest(Word,List)
  end;
end;

end.

