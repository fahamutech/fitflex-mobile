# Hero photo licences

Photos behind the photo heroes (`PHOTO_HERO_UI`, docs/design/photo-hero-screens.md). Interim stock until FitFlex has its own Dar es Salaam shoot. **No row, no ship.**

All files come from the parent repo's `social/brand/photos/` (branch `release-candidate`; record in `social/brand/photos/README.md` there). They were downloaded from Pexels on 2026-10-11; each photo page showed the licence label "Free" when checked on 2026-10-16 ([Pexels licence](https://www.pexels.com/license/): free to use and modify, no attribution required). None is marked AI-generated.

Processing (2026-10-19): cropped to the hero aspect ratio, converted to sRGB, resized, re-encoded as WebP (quality 72). Metadata (EXIF, GPS, ICC) is not carried over. 1x files sit in this folder, 2x files in `2.0x/`.

No photo shows an identifiable person, so no model releases are needed. No location or gym consent applies (the photos are not of FitFlex partner gyms and are not presented as such). No expiry.

| File | Used on | Source page | Photographer | Licence | Crop (source px, l,t,r,b) | 2x size | 2x bytes | 1x bytes | People |
|---|---|---|---|---|---|---|---|---|---|
| `hero_language.webp` | Language | https://www.pexels.com/photo/12250460/ "Treadmills at Gym" | Mario García | Pexels licence | 120,0,1020,1125 (4:5) | 864x1080 | 79,492 | 29,066 | none |
| `hero_sign_in.webp` | Sign in | https://www.pexels.com/photo/9545909/ "Equipments Inside the Gym" | TUBARONES PHOTOGRAPHY | Pexels licence | 350,0,1150,1000 (4:5) | 768x960 | 47,276 | 20,342 | none |
| `hero_sign_up.webp` | Create account (all roles) | https://www.pexels.com/photo/3916766/ "Black and Red Dumbbells on Brown Wooden Floor" | Andrea Piacquadio | Pexels licence | 262,0,1039,972 (4:5) | 768x960 | 33,530 | 14,770 | none |
| `hero_role.webp` | Choose role | https://www.pexels.com/photo/29526371/ "Modern well-equipped gym with diverse fitness equipment" | foad shariyati | Pexels licence | 0,420,1500,1264 (16:9) | 1280x720 | 113,856 | 45,572 | none |
| `hero_home_start.webp` | Home: no pass, pending, ended, loading, offline | https://www.pexels.com/photo/29526371/ (same as above) | foad shariyati | Pexels licence | 0,0,1500,1875 (4:5) | 864x1080 | 110,646 | 41,474 | none |
| `hero_home_pass.webp` | Home: active, few visits, ending soon | https://www.pexels.com/photo/5312212/ "Dumbbells in Close Up Photography" | Joel de la cruz | Pexels licence | 0,0,1491,994 (3:2) | 1080x720 | 24,256 | 10,758 | none (background blurred) |

Total added: 409,056 bytes at 2x + 161,982 bytes at 1x = 571,038 bytes (budget 1.2 MB).

These photos are not Tanzanian; they are a stop-gap (spec O-1). Replace with own photos before the flag is turned on in production.
