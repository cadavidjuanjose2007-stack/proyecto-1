% ============================================================
% Practica I - De los pixeles a la integral
% Solucion logica/declarativa en Prolog (SWI-Prolog)
% ST0244 - Programacion de Lenguajes
%
% Idea central del paradigma logico aplicada aqui:
%   No se describe "que instrucciones ejecutar" sino "que relacion debe
%   cumplirse" entre una imagen, una posicion X y su altura Altura:
%
%       f(X, Datos, Alto, BytesPorFila, Altura)
%
%   El vector de alturas M no se "construye" con un bucle: se OBTIENE
%   pidiendole a Prolog que encuentre TODOS los valores que satisfacen
%   esa relacion, con findall/3. El area es la suma de esa lista.
%
%       relaciones -> valores que satisfacen f(x) -> M -> area
% ============================================================

:- initialization(main).
:- set_stream(user_output, encoding(utf8)).

% ------------------------------------------------------------
% Punto de entrada
% ------------------------------------------------------------
main :-
    ( current_prolog_flag(argv, [ArchivoArg|_]) ->
        Archivo = ArchivoArg
    ;   Archivo = '../curva_binaria_P4.pbm'   % ejecucion desde Prolog/ (ver README)
    ),
    cargar_pbm(Archivo, Ancho, Alto, Datos),
    BytesPorFila is (Ancho + 7) // 8,
    MaxX is Ancho - 1,

    % --- El vector de alturas se obtiene declarativamente ---
    findall(Altura,
            ( between(0, MaxX, X),
              f(X, Datos, Alto, BytesPorFila, Altura) ),
            M),

    % --- El area es la relacion "M -> suma de M" ---
    sum_list(M, Area),

    format("Imagen: ~w x ~w pixeles~n", [Ancho, Alto]),
    format("Area = ~w pixeles cuadrados~n~n", [Area]),

    mostrar_muestras(M, Ancho),
    nl,
    visualizar_curva(M, 100, 25),
    nl,
    visualizar_alturas(M, 100),
    nl,
    halt.
main :-
    format("Error: no se pudo procesar el archivo PBM.~n"),
    halt(1).

% ============================================================
% 1-2. CARGA DEL ARCHIVO PBM P4 Y ACCESO A PIXELES INDIVIDUALES
% ============================================================

% cargar_pbm(+Archivo, -Ancho, -Alto, -Datos)
% Lee el archivo binario y separa el encabezado ("P4", comentarios,
% ancho, alto) de los bytes de pixeles empaquetados (8 pixeles/byte).
% Datos queda representado como una cadena (string) de SWI-Prolog para
% permitir acceso indexado en O(1) mediante string_code/3.
cargar_pbm(Archivo, Ancho, Alto, Datos) :-
    read_file_to_codes(Archivo, Codigos, [encoding(octet)]),
    Codigos = [0'P, 0'4 | Resto0],
    saltar_blancos_comentarios(Resto0, Resto1),
    leer_numero(Resto1, Ancho, Resto2),
    saltar_blancos_comentarios(Resto2, Resto3),
    leer_numero(Resto3, Alto, Resto4),
    Resto4 = [_UnEspacio | BytesPixeles],   % un solo separador tras "alto"
    string_codes(Datos, BytesPixeles).

% Salta espacios en blanco y comentarios "# ... \n"
saltar_blancos_comentarios([C|Cs], Salida) :-
    code_type(C, space), !,
    saltar_blancos_comentarios(Cs, Salida).
saltar_blancos_comentarios([0'# | Cs], Salida) :-
    !,
    saltar_linea(Cs, Cs2),
    saltar_blancos_comentarios(Cs2, Salida).
saltar_blancos_comentarios(Cs, Cs).

saltar_linea([], []) :- !.
saltar_linea([0'\n | Cs], Cs) :- !.
saltar_linea([_ | Cs], Salida) :- saltar_linea(Cs, Salida).

% Lee un token numerico (ancho o alto) al inicio de la lista de codigos
leer_numero(Codigos, Numero, Resto) :-
    leer_digitos(Codigos, DigitosCod, Resto),
    number_codes(Numero, DigitosCod).

leer_digitos([C|Cs], [C|Ds], Resto) :-
    code_type(C, digit), !,
    leer_digitos(Cs, Ds, Resto).
leer_digitos(Cs, [], Cs).

% pixel(+X, +Y, +Datos, +BytesPorFila, -Bit)
% Relacion que da el valor (0 o 1) del pixel (X,Y). 1 = negro.
pixel(X, Y, Datos, BytesPorFila, Bit) :-
    IdxByte is Y * BytesPorFila + (X // 8),
    Idx1 is IdxByte + 1,                 % string_code/3 es 1-based
    string_code(Idx1, Datos, Byte),
    PosBit is 7 - (X mod 8),
    Bit is (Byte >> PosBit) /\ 1.

es_negro(X, Y, Datos, BytesPorFila) :-
    pixel(X, Y, Datos, BytesPorFila, 1).

% ============================================================
% 3. LA RELACION f(X, Datos, Alto, BytesPorFila, Altura)
%    "Altura es la cantidad de pixeles negros consecutivos desde
%     abajo, en la columna X, antes de encontrar el primer blanco"
% ============================================================

f(X, Datos, Alto, BytesPorFila, Altura) :-
    YInicial is Alto - 1,
    contar_negros_desde(X, YInicial, Datos, BytesPorFila, Altura).

% contar_negros_desde(+X, +Y, +Datos, +BytesPorFila, -Altura)
% Relacion recursiva: si (X,Y) es negro, la altura es 1 mas la altura
% de la columna comenzando en la fila de arriba (Y-1); si es blanco (o
% Y < 0, borde de la imagen) la altura es 0. Esto es la version
% declarativa de "contar mientras sea negro".
contar_negros_desde(_, Y, _, _, 0) :-
    Y < 0, !.
contar_negros_desde(X, Y, Datos, BytesPorFila, Altura) :-
    Y >= 0,
    ( es_negro(X, Y, Datos, BytesPorFila) ->
        Y1 is Y - 1,
        contar_negros_desde(X, Y1, Datos, BytesPorFila, Altura1),
        Altura is Altura1 + 1
    ;   Altura = 0
    ).

% ============================================================
% 4-5. M y el AREA ya se obtuvieron en main/0 mediante
%      findall/3 + sum_list/2 (ver arriba). Esa es, literalmente,
%      la traduccion directa de:
%        M = [f(0), f(1), ..., f(n-1)]        (findall)
%        A = sum_{i=0}^{n-1} f(x_i)           (sum_list)
% ============================================================

% ============================================================
% 8. VALORES DE MUESTRA x_i -> f(x_i)
% ============================================================

mostrar_muestras(M, Ancho) :-
    length(M, N),
    N =:= Ancho,
    NPuntos = 10,
    UltimoIdx is NPuntos - 1,
    format("Algunos valores x_i -> f(x_i):~n"),
    forall(
        between(0, UltimoIdx, I),
        ( X is (I * (Ancho - 1)) // UltimoIdx,
          nth0(X, M, Altura),
          format("x_~w = ~w~t~10|-> f(x_~w) = ~w pixeles~n", [I, X, I, Altura])
        )
    ).

% ============================================================
% 6. VISUALIZACION DE LA CURVA (grilla ASCII escalada)
%
% Estrategia (misma que en la version Haskell, para que ambos
% programas sean comparables): se agrupan las columnas originales en
% AnchoTerm "cubos" y cada cubo se representa por el PROMEDIO de sus
% alturas; luego se escala verticalmente a AltoTerm filas y se dibuja
% de abajo hacia arriba.
% ============================================================

visualizar_curva(M, AnchoTerm, AltoTerm) :-
    format("Visualizacion de la curva (escalada a la consola):~n"),
    muestrear(M, AnchoTerm, Muestras),
    max_list(Muestras, MaxH0),
    MaxH is max(MaxH0, 1),
    maplist([H,E]>>(E is round((H / MaxH) * AltoTerm)), Muestras, Escaladas),
    forall(
        between(1, AltoTerm, R),
        ( Umbral is AltoTerm - R,
          fila_como_texto(Escaladas, Umbral, Linea),
          format("~s~n", [Linea])
        )
    ).

fila_como_texto([], _, []).
fila_como_texto([E|Es], Umbral, [C|Cs]) :-
    ( E >= Umbral -> C = 0'# ; C = 32 ),
    fila_como_texto(Es, Umbral, Cs).

% ============================================================
% 7. VISUALIZACION DE M[x] = f(x) COMO SPARKLINE UNICODE
%    (una sola linea, 8 niveles de bloque; complementa la grilla
%     del punto anterior mostrando M directamente, muestra a muestra)
% ============================================================

visualizar_alturas(M, AnchoTerm) :-
    format("Funcion de alturas M[x] = f(x) (sparkline Unicode):~n"),
    muestrear(M, AnchoTerm, Muestras),
    max_list(Muestras, MaxH0),
    MaxH is max(MaxH0, 1),
    Bloques = [32, 0x2581, 0x2582, 0x2583, 0x2584,
               0x2585, 0x2586, 0x2587, 0x2588],
    maplist([H,C]>>( Nivel0 is round((H / MaxH) * 8),
                      Nivel is max(0, min(8, Nivel0)),
                      nth0(Nivel, Bloques, C)
                    ), Muestras, Caracteres),
    string_codes(Linea, Caracteres),
    format("~s~n", [Linea]).

% ============================================================
% Utilidad compartida: reduce la lista M (longitud Ancho) a
% exactamente NCubos valores representativos, promediando cada grupo.
% ============================================================

muestrear(M, NCubos, Muestras) :-
    length(M, Ancho),
    findall(Promedio,
            ( between(0, NCubos, I0), I0 < NCubos,
              Ini is (I0 * Ancho) // NCubos,
              FinCand is ((I0 + 1) * Ancho) // NCubos,
              Fin is max(Ini + 1, FinCand),
              sublista(M, Ini, Fin, Sub),
              sum_list(Sub, SumaSub),
              length(Sub, Len),
              Promedio is SumaSub / Len
            ),
            Muestras).

% sublista(+Lista, +Ini, +Fin, -Sub) : elementos [Ini, Fin) de Lista
sublista(Lista, Ini, Fin, Sub) :-
    Largo is Fin - Ini,
    length(Prefijo, Ini),
    append(Prefijo, Resto, Lista),
    length(Sub, Largo),
    append(Sub, _, Resto).
