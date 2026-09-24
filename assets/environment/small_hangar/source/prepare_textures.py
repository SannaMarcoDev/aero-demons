"""Image-based grades of existing Poly Haven CC0 maps; no downloads.
Run with python3 + Pillow (already used by the project's asset tools).
"""
from pathlib import Path
from PIL import Image, ImageFilter, ImageChops
import math

BASE = Path(__file__).resolve().parents[1]
PH = BASE.parent / 'airport/textures/polyhaven'
OUT = BASE / 'textures'
OUT.mkdir(exist_ok=True)
N = 1024

def photo(name):
    return Image.open(PH / name).convert('RGB').resize((N,N))

roof = photo('ph_corrugated_roof_albedo.jpg')
Image.blend(roof,Image.new('RGB',roof.size,(115,120,120)),0.18).save(OUT/'roof_basecolor.jpg',quality=95)
noise = list(photo('concrete_floor_01_Diffuse.jpg').convert('L').getdata())
average = sum(noise)/len(noise)
paint, rough, grime = [], [], []
tracks = [sum(math.exp(-((x/(N-1)-t)/0.006)**2) for t in [0.04+i*0.115 for i in range(9)]) for x in range(N)]
for j,value in enumerate(noise):
    y,x = divmod(j,N)
    y /= N-1
    n = (value-average)/255
    dust = math.exp(-(1-y)*15)*(0.025+0.045*(n+0.5))
    streak = tracks[x]*(0.5+0.5*math.cos(y*4))*0.022
    paint.append(tuple(int(255*(c+n*0.13-streak+dust*d)) for c,d in zip((0.31,0.365,0.345),(0.65,0.36,0.1))))
    rough.append(int(255*(0.61+n*0.18+dust+streak)))
    grime.append((49,41,28,int(255*((y**3)*(0.14+0.1*(n+0.5))+streak*1.4*y))))
for name,mode,pixels in [('door_basecolor.jpg','RGB',paint),('door_roughness.png','L',rough),('ground_dirt.png','RGBA',grime)]:
    image=Image.new(mode,(N,N));image.putdata(pixels);image.save(OUT/name)
normal = photo('concrete_floor_01_nor_gl.jpg')
Image.blend(normal,Image.new('RGB',normal.size,(128,128,255)),0.94).save(OUT/'door_normal.png')
for source,target in {
    'ph_cast_concrete_albedo.jpg':'concrete_basecolor.jpg',
    'concrete_nor_gl.jpg':'concrete_normal.jpg',
    'concrete_Rough.jpg':'concrete_roughness.jpg',
    'ph_airfield_concrete_albedo.jpg':'floor_basecolor.jpg',
    'concrete_floor_01_nor_gl.jpg':'floor_normal.jpg',
    'concrete_floor_01_Rough.jpg':'floor_roughness.jpg',
    'corrugated_iron_02_nor_gl.jpg':'roof_normal.jpg',
    'corrugated_iron_02_Rough.jpg':'roof_roughness.jpg',
}.items():
    photo(source).save(OUT/target,quality=95)
print('PASS: 13 authored/downsized 1K PBR/decal maps from existing CC0 sources')
