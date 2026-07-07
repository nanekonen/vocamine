String partOfSpeechLabel(String partOfSpeech) {
  switch (partOfSpeech) {
    case 'noun':
      return '名詞';
    case 'verb':
      return '動詞';
    case 'adjective':
      return '形容詞';
    case 'adverb':
      return '副詞';
    case 'pronoun':
      return '代名詞';
    case 'preposition':
      return '前置詞';
    case 'conjunction':
      return '接続詞';
    case 'interjection':
      return '間投詞';
    case 'determiner':
      return '限定詞';
    case 'article':
      return '冠詞';
    case 'auxiliary':
      return '助動詞';
    case 'numeral':
      return '数詞';
    case 'prefix':
      return '接頭辞';
    case 'suffix':
      return '接尾辞';
    case 'phrase':
      return '熟語';
    case 'abbreviation':
      return '略語';
    default:
      return partOfSpeech;
  }
}

String? partOfSpeechDetailLabel(String? detail) {
  switch (detail) {
    case 'article':
      return '冠詞';
    case 'demonstrative':
      return '指示詞';
    case 'possessive_determiner':
      return '所有格';
    case 'quantifier':
      return '数量詞';
    case 'numeral':
      return '数詞';
    case 'modal_auxiliary':
      return '法助動詞';
    case 'auxiliary':
      return '助動詞';
    case 'copula':
      return 'be動詞・連結動詞';
    default:
      return null;
  }
}
