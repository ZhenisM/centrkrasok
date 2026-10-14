import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// «Потенциальный проект» — та же форма Битрикс24 (CRM-форма 205), что
/// на странице /new_projects/ сайта, с той же подсказкой дизайнеров по
/// полю «ФИО Дизайнера» (база партнёров ИП Мамиев — как GET_PARTNERS).
class PotentialProjectScreen extends StatefulWidget {
  const PotentialProjectScreen({super.key});
  @override
  State<PotentialProjectScreen> createState() => _PotentialProjectScreenState();
}

class _PotentialProjectScreenState extends State<PotentialProjectScreen> {
  WebViewController? _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => mounted ? setState(() => _loading = false) : null,
      ));
    // baseUrl = prons.kz — подсказка дизайнеров ходит на /ajax/centrkrasok/
    // того же домена (без CORS).
    await c.loadHtmlString(_html(token), baseUrl: 'https://prons.kz/');
    if (mounted) setState(() => _controller = c);
  }

  String _html(String token) => '''<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
 /* Стили формы — как на странице /new_projects/ сайта, плюс адаптация
    под телефон и цвета приложения. */
 body{margin:0;padding:6px;font-family:-apple-system,Roboto,sans-serif;background:#F3F2F7}
 .b24-window-panel{max-width:100%}
 .b24-form-wrapper{max-width:100%;border-radius:16px;border-bottom:none}
 .b24-form-wrapper.b24-form-border-bottom{border-bottom:none}
 .b24-form-control{cursor:pointer}
 .b24-form-control-text .b24-form-control,.b24-form-control-list .b24-form-control,
 .b24-form-control-string .b24-form-control{--b24-field-background-color:#fff;border-radius:12px}
 .b24-form-control-text .b24-form-control:focus:not([readonly]),
 .b24-form-control-string .b24-form-control:focus:not([readonly]){border-color:#26933b}
 .b24-form-control-radio,.b24-form-control-checkbox{background-color:#fff}
 .b24-form-control-radio .b24-form-control,.b24-form-control-checkbox .b24-form-control{
   border:1.5px solid #26933b!important;background-color:#fff;min-height:44px;margin:0;border-radius:12px;
   box-shadow:none}
 /* Выбранный вариант — зелёный, как на сайте (#26933b). !important —
    форма Битрикс24 подгружает свои стили ПОСЛЕ наших и иначе красит
    выбранный вариант синим. */
 .b24-form-control-radio .b24-form-control.b24-form-control-checked,
 .b24-form-control-checkbox .b24-form-control.b24-form-control-checked,
 .b24-form .b24-form-control-radio .b24-form-control.b24-form-control-checked,
 .b24-form .b24-form-control-checkbox .b24-form-control.b24-form-control-checked{
   background-color:#26933b!important;border-color:#26933b!important;--b24-primary-color:#26933b}
 .b24-form input[type=radio],.b24-form input[type=checkbox]{accent-color:#26933b}
 .b24-form{--b24-primary-color:#26933b;--b24-primary-hover-color:#217431;--b24-primary-text-color:#fff}
 .b24-form-control-radio .b24-form-control.b24-form-control-checked .b24-form-control-desc,
 .b24-form-control-checkbox .b24-form-control.b24-form-control-checked .b24-form-control-desc{color:#fff}
 .b24-form-field.b24-form-field-radio.b24-form-control-radio .b24-form-control-container > fieldset,
 .b24-form-field.b24-form-field-checkbox .b24-form-control-container > fieldset{
   display:grid;grid-template-columns:1fr 1fr;gap:8px;border:none;padding:0;margin:0}
 .b24-form-field.b24-form-field-radio.b24-form-control-radio .b24-form-control-container > fieldset > .b24-form-control-label,
 .b24-form-field.b24-form-field-checkbox .b24-form-control-container > fieldset > .b24-form-control-label{
   grid-column:1 / -1;margin-bottom:2px}
 @media (max-width:340px){
  .b24-form-field.b24-form-field-radio.b24-form-control-radio .b24-form-control-container > fieldset,
  .b24-form-field.b24-form-field-checkbox .b24-form-control-container > fieldset{grid-template-columns:1fr}
 }
 .b24-form-btn{background-color:#26933b!important;border-radius:14px!important;min-height:52px}
 .b24-form-btn:active,.b24-form-btn:hover{background-color:#217431!important}
 .designer-result{position:relative;z-index:50}
 .designer-result-list{position:absolute;left:0;right:0;max-height:260px;overflow:auto;background:#fff;
   border:1px solid #ddd;border-radius:12px;box-shadow:0 6px 18px rgba(0,0,0,.12)}
 .designer-btn{display:block;width:100%;text-align:left;padding:12px 14px;border:0;border-bottom:1px solid #eee;
   background:#fff;font-size:15px}
</style></head><body>
<script>
 var TOKEN = ${jsonEncode(token)};
 var designerTimer;
 window.addEventListener('b24:form:init', function(e){
  var form = e.detail.object;
  if (form.identification.id != 205) return;
  document.addEventListener('input', function(ev){
   var input = ev.target;
   if (!input.classList || !input.classList.contains('b24-form-control')) return;
   var label = input.parentNode ? input.parentNode.querySelector('.b24-form-control-label') : null;
   if (!label || label.textContent.indexOf('ФИО Дизайнера') === -1) return;
   clearTimeout(designerTimer);
   designerTimer = setTimeout(async function(){
    var old = document.getElementById('designer-result'); if (old) old.remove();
    var q = input.value.trim(); if (q.length < 3) return;
    var fd = new FormData();
    fd.set('token', TOKEN); fd.set('action', 'partners'); fd.set('q', q); fd.set('person_type', '6');
    try {
     var r = await fetch('/ajax/centrkrasok/order.php', {method:'POST', body: fd});
     var data = await r.json();
     var list = (data.result && data.result.partners) || [];
     if (!list.length) return;
     var box = document.createElement('div'); box.className='designer-result'; box.id='designer-result';
     var ul = document.createElement('div'); ul.className='designer-result-list';
     list.forEach(function(d){
      var b = document.createElement('button'); b.type='button'; b.className='designer-btn';
      b.textContent = d.bin ? (d.name + ' [' + d.bin + ']') : d.name;
      b.onclick = function(){
       input.value = d.name;
       form.setValues({DEAL_UF_CRM_1771593574315: d.name});
       box.remove();
      };
      ul.appendChild(b);
     });
     box.appendChild(ul); input.parentNode.appendChild(box);
    } catch(err) {}
   }, 500);
  });
 });
</script>
<script data-b24-form="inline/205/hq6ca0" data-skip-moving="true">(function(w,d,u){var s=d.createElement('script');s.async=true;s.src=u+'?'+(Date.now()/180000|0);var h=d.getElementsByTagName('script')[0];h.parentNode.insertBefore(s,h);})(window,document,'https://cdn-ru.bitrix24.kz/b7517553/crm/form/loader_205.js');</script>
</body></html>''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        title: const Text('Потенциальный проект', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Stack(children: [
        if (_controller != null) WebViewWidget(controller: _controller!),
        if (_loading) const LinearProgressIndicator(color: Color(0xFF4CAF50), backgroundColor: Color(0xFFE8F5E9)),
      ]),
    );
  }
}
