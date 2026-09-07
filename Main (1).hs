-- Practica I - De los pixeles a la integral
-- Solucion funcional en Haskell
-- Autor del enunciado: Alexander Narvaez (ST0244)
--
-- Idea central del paradigma funcional aplicada aqui:
--   La estructura de alturas M es el resultado de APLICAR una funcion f
--   a todo el dominio:            M = map f [0 .. ancho - 1]
--   El area es una PLEGADO (fold) sobre esa estructura:  area = sum M
--
-- Toda la transformacion se ve como una tuberia de funciones puras:
--   PBM (bytes) -> pixel (x,y) -> f(x) -> M -> area
--
module Main (main) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import           Data.Bits        (testBit)
import           Data.Char        (isSpace, isDigit)
import           Data.Word        (Word8)
import           Text.Printf      (printf)
import           System.IO        (hSetEncoding, stdout, utf8)
import           System.Environment (getArgs)

-- ---------------------------------------------------------------------
-- 1. Representacion de una imagen PBM P4 ya cargada en memoria
-- ---------------------------------------------------------------------

data PBM = PBM
  { ancho     :: !Int          -- width  (columnas)
  , alto      :: !Int          -- height (filas)
  , pixelData :: !BS.ByteString -- bytes empaquetados (8 pixeles/byte)
  }

-- ancho de una fila en BYTES (no en pixeles): cada byte trae 8 pixeles
bytesPorFila :: Int -> Int
bytesPorFila w = (w + 7) `div` 8

-- ---------------------------------------------------------------------
-- 2. Carga y parseo del encabezado binario PBM P4
--    Formato:  "P4" WS* (comentarios '#'...\n)* ancho WS alto WS <bytes>
-- ---------------------------------------------------------------------

cargarPBM :: FilePath -> IO PBM
cargarPBM ruta = do
  contenido <- BS.readFile ruta
  let sinMagic            = BS.drop 2 contenido            -- descarta "P4"
      (w, resto1)          = leerEntero (saltarBlancos sinMagic)
      (h, resto2)          = leerEntero (saltarBlancos resto1)
      datos                = BS.drop 1 resto2               -- 1 whitespace separador
  pure (PBM w h datos)

esBlancoOComentario :: Word8 -> Bool
esBlancoOComentario b = isSpace (toEnum (fromIntegral b))

-- Salta espacios en blanco y lineas de comentario que empiezan con '#'
saltarBlancos :: BS.ByteString -> BS.ByteString
saltarBlancos bs
  | BS.null bs = bs
  | esBlancoOComentario (BS.head bs) = saltarBlancos (BS.tail bs)
  | BS.head bs == fromIntegral (fromEnum '#') =
      saltarBlancos (BS.drop 1 (BSC.dropWhile (/= '\n') bs))
  | otherwise = bs

-- Lee un numero decimal (ancho o alto) al inicio del ByteString
leerEntero :: BS.ByteString -> (Int, BS.ByteString)
leerEntero bs =
  let (tok, resto) = BSC.span isDigit bs
  in (read (BSC.unpack tok), resto)

-- ---------------------------------------------------------------------
-- 3. Acceso a un pixel individual (x,y).  True = negro (bit = 1)
-- ---------------------------------------------------------------------

esNegro :: PBM -> Int -> Int -> Bool
esNegro img x y =
  let rb       = bytesPorFila (ancho img)
      idxByte  = y * rb + (x `div` 8)
      byte     = BS.index (pixelData img) idxByte
      bitPos   = 7 - (x `mod` 8)      -- el bit mas significativo es el pixel mas a la izquierda
  in testBit byte bitPos

-- ---------------------------------------------------------------------
-- 4. La funcion discreta f(x): pixeles negros consecutivos desde abajo
-- ---------------------------------------------------------------------

f :: PBM -> Int -> Int
f img x = length (takeWhile id [ esNegro img x y | y <- [alto img - 1, alto img - 2 .. 0] ])

-- ---------------------------------------------------------------------
-- 5. La estructura de alturas M = map f [0 .. ancho-1]
--    y el area como un fold puro:  area = sum M
-- ---------------------------------------------------------------------

vectorAlturas :: PBM -> [Int]
vectorAlturas img = map (f img) [0 .. ancho img - 1]

area :: [Int] -> Int
area = sum

-- ---------------------------------------------------------------------
-- 6. Visualizacion en consola de la curva (grilla ASCII escalada)
--
-- Estrategia de escalado (justificada en el README):
--   * Columnas: se agrupan las `ancho` columnas originales en `tw` "cubos"
--     (buckets) de tamano aprox. ancho/tw; cada cubo se representa con el
--     PROMEDIO de las alturas originales que caen en el (preserva la forma
--     general sin depender de un unico pixel ruidoso).
--   * Filas: la altura maxima de esos promedios se escala linealmente a
--     `th` filas de terminal, y se dibuja de abajo hacia arriba.
-- ---------------------------------------------------------------------

promedioEnRango :: [Int] -> Int -> Int -> Double
promedioEnRango xs ini fin =
  let sub = take (fin - ini) (drop ini xs)
  in if null sub then 0 else fromIntegral (sum sub) / fromIntegral (length sub)

-- Reduce la lista m (longitud w) a exactamente tw valores representativos
muestrear :: [Int] -> Int -> [Double]
muestrear m tw =
  let w = length m
  in [ promedioEnRango m (i * w `div` tw) (max ((i * w `div` tw) + 1) ((i + 1) * w `div` tw))
     | i <- [0 .. tw - 1] ]

dibujarCurva :: [Int] -> Int -> Int -> String
dibujarCurva m tw th =
  let muestras   = muestrear m tw
      maxH       = maximum (1 : map round muestras)
      escalada   = [ round ((h / fromIntegral maxH) * fromIntegral th) | h <- muestras ] :: [Int]
      fila r     = [ if col >= th - r then '#' else ' ' | col <- escalada ]
  in unlines [ fila r | r <- [1 .. th] ]

-- ---------------------------------------------------------------------
-- 7. Visualizacion de M[x] = f(x) como "sparkline" Unicode (una sola
--    linea, 8 niveles de bloque). Es una representacion complementaria
--    a la grilla del punto 6: aq ui cada caracter ES directamente una
--    muestra de M, no una fila de la imagen.
-- ---------------------------------------------------------------------

bloques :: String
bloques = " \9601\9602\9603\9604\9605\9606\9607\9608"  -- ' ' ▁▂▃▄▅▆▇█

sparkline :: [Int] -> Int -> String
sparkline m tw =
  let muestras = muestrear m tw
      maxH     = maximum (1 : map round muestras)
      nivel h  = round ((h / fromIntegral maxH) * 8) :: Int
  in [ bloques !! min 8 (max 0 (nivel h)) | h <- muestras ]

-- ---------------------------------------------------------------------
-- 8. Valores de muestra x_i -> f(x_i), 10 posiciones distribuidas
-- ---------------------------------------------------------------------

valoresMuestra :: [Int] -> Int -> [(Int, Int)]
valoresMuestra m n =
  let w = length m
      xs = [ (i * (w - 1)) `div` (n - 1) | i <- [0 .. n - 1] ]
  in [ (x, m !! x) | x <- xs ]

-- ---------------------------------------------------------------------
-- main: encadena todo   PBM -> bytes -> pixeles -> f -> M -> area
-- ---------------------------------------------------------------------

main :: IO ()
main = do
  hSetEncoding stdout utf8
  args <- getArgs
  -- Por defecto se asume que el programa se ejecuta desde Haskell/ y que
  -- el .pbm esta un nivel arriba, en la raiz del repositorio (ver README).
  -- Tambien se puede indicar la ruta explicitamente: ./area ruta.pbm
  let archivo = case args of
        (ruta : _) -> ruta
        []         -> "../curva_binaria_P4.pbm"
  img <- cargarPBM archivo

  let m   = vectorAlturas img          -- M = map f [0 .. ancho-1]
      a   = area m                     -- area = sum M

  printf "Imagen: %d x %d pixeles\n" (ancho img) (alto img)
  printf "Area = %d pixeles cuadrados\n\n" a

  putStrLn "Visualizacion de la curva (escalada a la consola):"
  putStrLn (dibujarCurva m 100 25)

  putStrLn "Funcion de alturas M[x] = f(x)  (sparkline Unicode):"
  putStrLn (sparkline m 100)
  putStrLn ""

  putStrLn "Algunos valores x_i -> f(x_i):"
  mapM_ (\(i, (x, h)) -> printf "x_%d = %-4d -> f(x_%d) = %d pixeles\n" i x i h)
        (zip [0 :: Int ..] (valoresMuestra m 10))
