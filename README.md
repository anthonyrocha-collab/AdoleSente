# AdoleSente

Espaço diário de apoio para pré-adolescentes (ODS 4 · Educação de Qualidade): um diário com senha, uma sugestão do dia, perguntas aleatórias e um grupo de personagens para conhecer. Visual "Frutiger Metro", mobile-first, tema escuro fixo.

## O que vem neste projeto

```
adolesente/
├── public/index.html        ← o app inteiro (HTML + CSS + JS puros, sem build)
├── vercel.json              ← deploy na Vercel (publica a pasta public/)
├── package.json             ← scripts para rodar localmente
├── .env.example             ← variáveis para quando ligar ao Supabase
├── supabase/
│   ├── schema.sql           ← tabelas + RLS estrito
│   └── seed.sql             ← personagens, sugestões, perguntas e ideias do diário
└── docs/INTEGRACAO-SUPABASE.md  ← como ligar o app ao Supabase, passo a passo
```

**Estado atual do app:** ele funciona 100% sozinho. Todos os dados (perfil, senha de acesso, diário criptografado, respostas, cores) ficam no `localStorage` do navegador. O Supabase, descrito abaixo, é o próximo passo e **ainda não está ligado ao código**: o `schema.sql` já está pronto e testado, e o guia em `docs/` explica como fazer a ligação.

---

## 1. Rodar localmente

Precisa do Node 18+ (só para servir a pasta).

```bash
npm run dev
# abre http://localhost:3000
```

Ou abra `public/index.html` direto no navegador.

## 2. Subir para o GitHub

```bash
git init
git add .
git commit -m "AdoleSente: primeira versão"
git branch -M main
git remote add origin https://github.com/SEU-USUARIO/adolesente.git
git push -u origin main
```

`.env` já está no `.gitignore`. Nunca suba chaves secretas.

## 3. Deploy na Vercel

1. Em [vercel.com/new](https://vercel.com/new), importe o repositório do GitHub.
2. **Framework Preset:** `Other`. Não precisa de Build Command nem Install Command (o `vercel.json` já cuida disso e publica `public/`).
3. Clique em **Deploy**.

A partir daí, cada `git push` na `main` gera um deploy de produção, e cada branch ou pull request gera uma URL de preview.

Por linha de comando: `npm i -g vercel && vercel --prod`.

## 4. Supabase

1. Crie um projeto em [supabase.com](https://supabase.com).
2. **SQL Editor** → cole o conteúdo de `supabase/schema.sql` → **Run**.
3. Ainda no SQL Editor → cole `supabase/seed.sql` → **Run**.
4. **Authentication → Providers:** habilite Email (e, se quiser, Google).
5. **Project Settings → API:** copie `Project URL` e a chave `anon public`.
6. Na Vercel: **Settings → Environment Variables**, adicione `SUPABASE_URL` e `SUPABASE_ANON_KEY` (modelo no `.env.example`).
7. Siga `docs/INTEGRACAO-SUPABASE.md` para trocar o armazenamento local pelo Supabase.

### Tabelas

| Tabela | Para quê | Quem acessa |
|---|---|---|
| `profiles` | nome, pronomes, ícone, cores, tamanho do texto | só o dono |
| `diary_keys` | chaves do diário, já embrulhadas no navegador | só o dono |
| `notes` | páginas do diário, **sempre criptografadas** | só o dono |
| `answers` | respostas às perguntas da sessão | só o dono |
| `characters`, `suggestions`, `questions`, `diary_ideas` | conteúdo do app | leitura pública, escrita só pelo painel |

### Segurança

- **RLS ligado em todas as tabelas.** Um usuário nunca lê nem altera nota de outro. Isso foi testado num Postgres real: inserir em nome de outro usuário é bloqueado, e outro usuário enxerga 0 notas alheias.
- **Diário criptografado de ponta a ponta** (AES-GCM com chave derivada da senha por PBKDF2). O servidor guarda só texto cifrado. A consequência: se o usuário perder a senha **e** a chave de recuperação, nem você consegue recuperar o diário. Isso é proposital.
- A chave `anon` pode ficar no front-end. A `service_role` **nunca**.
- O público é pré-adolescente: antes de abrir cadastro para menores, confira a LGPD (art. 14, dados de crianças e adolescentes) e a política de privacidade que você vai publicar.

## Como o app é organizado

Um arquivo só (`public/index.html`), sem dependências. O estado inteiro vive em um objeto `S`, salvo em `localStorage` na chave `adolesente.v1`. As cores são variáveis CSS; os textos, personagens, sugestões e perguntas ficam em `defaults()` dentro do script.

## Licença

Defina a sua. Sem licença, o código fica com todos os direitos reservados.
