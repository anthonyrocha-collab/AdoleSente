# Ligando o AdoleSente ao Supabase

Hoje o app lê e grava tudo em `localStorage` (função `load()` e `save()` em `public/index.html`). Este guia mostra como trocar isso pelo Supabase **sem mudar a criptografia do diário**.

> Antes de começar: rode `supabase/schema.sql` e `supabase/seed.sql` (veja o README).

## 1. Mapa: o que hoje está onde

| No app (`S.…`) | Vai para o Supabase |
|---|---|
| `S.profile` (name, pronouns, avatar, textSize) e `S.theme.layout` | `profiles` |
| `S.profile.colors`, `S.diaryStyle` | `profiles.colors`, `profiles.diary_style` |
| `S.tut.asked` | `profiles.tutorial_asked` |
| `S.profile.auth` (senha de acesso local) | **sai**: o login passa a ser do Supabase Auth |
| `S.diary` (salt, wk, rsalt, rwk) | `diary_keys` |
| `S.diary.data` (todas as páginas num bloco) | `notes` (uma linha cifrada por página) |
| `S.answers` | `answers` |
| `S.characters`, `S.suggestions`, `S.questions`, `IDEAS` | `characters`, `suggestions`, `questions`, `diary_ideas` |

## 2. Cliente

Como o app é um HTML único, o jeito mais simples é carregar o cliente por CDN antes do script principal:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script>
  // Em produção, injete estes dois valores no build (ou deixe fixos aqui: a chave anon é pública).
  window.sb = supabase.createClient("https://SEU-PROJETO.supabase.co", "SUA-CHAVE-ANON");
</script>
```

Se preferir variáveis de ambiente de verdade, migre para Vite (`npm create vite@latest`) e use `import.meta.env.VITE_SUPABASE_URL`. Na Vercel, o prefixo `VITE_` é obrigatório para a variável chegar ao navegador.

## 3. Login (substitui a senha de acesso local)

```js
// cadastro
const { error } = await sb.auth.signUp({ email, password });
// entrar
const { data, error } = await sb.auth.signInWithPassword({ email, password });
// sair  (equivale a "Encerrar sessão")
await sb.auth.signOut();
// recuperar a senha de acesso por e-mail  (substitui a "chave de acesso" local)
await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin });
```

Com isso, **a recuperação de dados por e-mail** (que ficou em espera) passa a funcionar sozinha: o perfil, as respostas e o diário cifrado ficam na conta, e o usuário entra de qualquer aparelho. Em Authentication → URL Configuration, cadastre a URL da Vercel.

Dica: como o público é pré-adolescente, considere pedir o e-mail de um responsável e ativar a confirmação de e-mail (Authentication → Providers → Email → *Confirm email*).

## 4. Perfil, respostas e conteúdo

```js
// ler o perfil
const { data: profile } = await sb.from("profiles").select("*").single();
// salvar mudanças
await sb.from("profiles").update({ name, pronouns, avatar, colors, text_size: 125 })
        .eq("id", (await sb.auth.getUser()).data.user.id);

// respostas da sessão
await sb.from("answers").insert({ user_id: uid, question, answer });
const { data: answers } = await sb.from("answers").select("*").order("created_at", { ascending: false });

// conteúdo público
const { data: characters }  = await sb.from("characters").select("*").order("position");
const { data: suggestions } = await sb.from("suggestions").select("*");
```

O RLS já garante que cada usuário só enxerga o que é dele; não filtre por `user_id` achando que isso protege: a proteção é do banco.

## 5. Diário: manter a criptografia de ponta a ponta

Hoje o app usa **envelope encryption**:

- `DEK`: chave AES-GCM aleatória, gerada no navegador, que cifra as páginas.
- `wk`: a DEK cifrada pela chave derivada da **senha do diário** (PBKDF2 150 mil iterações).
- `rwk`: a DEK cifrada pela chave derivada da **chave de recuperação**.

Para o Supabase, mude só **onde os bytes são guardados**:

1. Guarde `{salt, wk, rsalt, rwk}` em `diary_keys` (uma linha por usuário). Funções do app envolvidas: `mk()` (criação), `op()` (abrir), o fluxo de recuperação e "Segurança do diário".
2. Em vez de cifrar **todas** as páginas num bloco (`encryptNotes()`), cifre **cada página** com a mesma DEK e um IV novo, e grave em `notes`:

```js
async function saveNote(n) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, D.key,
              enc.encode(JSON.stringify({ title: n.title, text: n.text, date: n.date })));
  await sb.from("notes").upsert({ id: n.id, user_id: uid, iv: b64(iv), ciphertext: b64(ct) });
}
```

3. Ao abrir o diário, leia as linhas de `notes`, decifre cada uma com a DEK e monte `D.notes`.
4. Mantenha o debounce de 500 ms que o app já usa ao digitar, para não gravar a cada tecla.

**Atenção:** nunca envie senha, chave de recuperação ou DEK em texto aberto ao Supabase. Se enviar, perde a garantia de que nem você consegue ler o diário.

## 6. Migrar quem já usa a versão local

Quem já tem dados no `localStorage` não deve perdê-los. Sugestão: depois do primeiro login, se existir `adolesente.v1`, ofereça "Levar meus dados para a conta", faça os `insert`/`upsert` acima e só então apague o local.

## 7. Checklist antes de abrir ao público

- [ ] RLS ativo em todas as tabelas (já vem no `schema.sql`; confira no painel, aba *Table Editor*).
- [ ] Confirmação de e-mail ligada.
- [ ] URL da Vercel em *Authentication → URL Configuration*.
- [ ] Política de privacidade e termos publicados (LGPD, art. 14, para menores).
- [ ] Nenhuma `service_role` no código nem no GitHub.
