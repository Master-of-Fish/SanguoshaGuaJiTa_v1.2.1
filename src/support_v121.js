// Voluntary support links. No payment or personal data is handled in-game.
(()=>{
  let body=document.querySelector('.page[data-page="settings"] .card-body');
  if(!body?.appendChild||!document.head?.appendChild||document.getElementById('supportAuthorCard'))return;
  let style=document.createElement('style');
  style.textContent='.support-author-card{margin-top:14px;padding:14px;border:1px solid var(--line2);background:var(--surface2)}.support-author-card p{margin:6px 0 10px}.support-author-card a{text-decoration:none;display:inline-flex;align-items:center}.support-author-card>span{display:block;margin-top:8px;font-size:12px;color:var(--muted)}';
  document.head.appendChild(style);
  let wrap=document.createElement('section');
  wrap.id='supportAuthorCard';wrap.className='support-author-card';
  wrap.innerHTML='<b>支持作者</b><p>游戏免费游玩。如果它给你带来快乐，可以自愿支持后续维护与更新。</p><div class="actions"><a class="btn primary" href="https://afdian.com/a/Master-of-Fish" target="_blank" rel="noopener noreferrer">前往爱发电支持</a><a class="btn" href="https://github.com/Master-of-Fish" target="_blank" rel="noopener noreferrer">作者 GitHub</a></div><span>赞助完全自愿，不影响游戏内容、数值和存档。</span>';
  body.appendChild(wrap);
})();
